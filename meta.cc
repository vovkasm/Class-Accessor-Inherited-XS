#include "xs/meta.h"
#include "xs/common.h"
#include <new>

namespace caixs { namespace meta {

typedef AV* PackageMeta;

static MGVTBL package_marker;

static int field_meta_free(pTHX_ SV*, MAGIC* mg);

struct FieldMeta {
    SV* name;
    SV* required;
    SV* default_value;
};


#define FIELDS_PREALLOCADED 5
#define FIELD_SV_COUNT 3

static PackageMeta find_package(HV* stash) {
    MAGIC* mg = CAIXS_mg_findext((SV*)stash, PERL_MAGIC_ext, &package_marker);
    return (PackageMeta)(mg ? mg->mg_obj : NULL);
}

static PackageMeta create_package(HV* stash) {
    AV* meta = newAV();
    av_extend(meta, FIELDS_PREALLOCADED * FIELD_SV_COUNT);

    sv_magicext((SV*)stash, (SV*)meta, PERL_MAGIC_ext, &package_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)meta);
    SvRMAGICAL_off((SV*)stash);

    return meta;
}

inline size_t size(PackageMeta meta) { return (AvFILLp(meta) + 1) / FIELD_SV_COUNT;}

void record(PackageMeta meta, SV* hash_key, SV* required, SV* default_value) {
    FieldMeta* fields = (FieldMeta*)AvARRAY(meta);

    STRLEN name_len;
    char* name = SvPV(hash_key, name_len);

    /* check that there might be already field meta is defined*/
    size_t fields_sz = size(meta);
    for(size_t i = 0; i < fields_sz; ++i) {
        STRLEN field_len;
        char* field_name = SvPV(fields[i].name, field_len);
        if (field_len != name_len) continue;

        if (strcmp(name, field_name) == 0) {
            croak("object key '%' is already defined", name);
        }
    }

    if (SvOK(default_value) && (!SvROK(default_value) || SvTYPE(SvRV(default_value)) != SVt_PVCV))
        croak("'default' should be a code reference");

    size_t new_sz = AvFILLp(meta) + FIELD_SV_COUNT;
    av_fill(meta, new_sz);

    SvREFCNT_inc_simple_NN(hash_key);
    SvREFCNT_inc_simple(default_value);
    FieldMeta& field = fields[fields_sz];

    field.name = hash_key;
    field.required = SvTRUE(required) ? &PL_sv_yes : NULL;
    field.default_value = default_value;
}

void activate(PackageMeta meta, SV *sv) {
    HV* hv = (HV*)SvRV(sv);

    FieldMeta* fields = (FieldMeta*)AvARRAY(meta);
    size_t fields_sz = size(meta);
    for(size_t i = 0; i < fields_sz; ++i) {
        FieldMeta& field = fields[i];

        STRLEN field_len;
        char* field_name = SvPV(field.name, field_len);

        if (SvOK(field.default_value)) {
            SV** value = hv_fetch(hv, field_name, field_len, 0);
            if (!value) {
                dSP;
                PUSHMARK(SP);
                int count = call_sv(fields->default_value, G_SCALAR | G_NOARGS);
                SPAGAIN;

                if (count != 1) croak("unexpected return from 'default': %d, expected: 1", count);

                SV* new_val = POPs;
                SvREFCNT_inc(new_val);
                SV** ok = hv_store(hv, field_name, field_len, new_val, 0);
                if (!ok) SvREFCNT_dec(new_val);
                PUTBACK;
            }
        } else if (field.required == &PL_sv_yes) {
            SV** value = hv_fetch(hv, field_name, field_len, 0);
            if (!value) croak("key '%s' is required", field_name);
            return;
        }
    }
}

// API-helpers

void install (CV *cv, SV* hash_key, SV* required, SV *default_value) {
    GV* gv = CvGV(cv);
    if (!gv) croak("cant get CV's glob");

    HV* stash = GvSTASH(gv);
    if (!stash) croak("can't get stash");

    PackageMeta meta = find_package(stash);
    if (!meta) meta = create_package(stash);
    if (!meta) return;

    record(meta, hash_key, required, default_value);
}

void activate(HV* stash, SV* object) {
    PackageMeta meta = find_package(stash);
    if (!meta) return;

    activate(meta, object);
}



}}




