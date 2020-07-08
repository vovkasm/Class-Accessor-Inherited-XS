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
    SV* default_code;
    SV* default_value;
};


#define FIELDS_PREALLOCADED 5
#define FIELD_SV_COUNT (sizeof (FieldMeta) / sizeof (SV*))

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

    /* check that there might be already field meta is defined*/
    size_t fields_sz = size(meta);
    for(size_t i = 0; i < fields_sz; ++i) {
        if (sv_eq(fields[i].name, hash_key)) {
            SV* err = newSV(0);
            sv_catpvf(err, "object key '%" SVf "' is already defined", hash_key);
            croak_sv(err);
        }
    }

    size_t new_sz = AvFILLp(meta) + FIELD_SV_COUNT;
    av_fill(meta, new_sz);
    FieldMeta& field = fields[fields_sz];

    if (default_value && SvOK(default_value)) {
        if (SvROK(default_value)) {
            if (SvTYPE(SvRV(default_value)) == SVt_PVCV) {
                field.default_code = SvREFCNT_inc_simple_NN(default_value);
            }
            else {
                SV* err = newSV(0);
                sv_catpvf(err, "Default values for '%" SVf "' should be either simple (string, number) or code ref", hash_key);
                croak_sv(err);
            }
        }
        else field.default_value = SvREFCNT_inc_simple_NN(default_value);
    }

    SvREFCNT_inc_simple_NN(hash_key);

    field.name = hash_key;
    field.required = SvTRUE(required) ? &PL_sv_yes : NULL;
}

void activate(PackageMeta meta, SV *sv) {
    HV* hv = (HV*)SvRV(sv);

    FieldMeta* fields = (FieldMeta*)AvARRAY(meta);
    size_t fields_sz = size(meta);
    for(size_t i = 0; i < fields_sz; ++i) {
        FieldMeta& field = fields[i];

        HE* value = hv_fetch_ent(hv, field.name, 0, 0);
        if (value) continue;

        if (field.default_code) {
            dSP;

            ENTER;
            SAVETMPS;

            PUSHMARK(SP);
            XPUSHs(sv);
            PUTBACK;
            int count = call_sv(fields->default_code, G_SCALAR);
            SPAGAIN;

            if (count != 1) {
                SV* err = newSV(0);
                sv_catpvf(err, "unexpected return from 'default' of '%" SVf "': %d insead of expected 1", field.name, count);
                croak_sv(err);
            }

            SV* new_val = POPs;
            SvREFCNT_inc(new_val);
            HE* ok = hv_store_ent(hv, field.name, new_val, 0);
            if (!ok) SvREFCNT_dec(new_val);

            PUTBACK;
            FREETMPS;
            LEAVE;
        } else if (field.default_value) {
            SvREFCNT_inc(field.default_value);
            HE* ok = hv_store_ent(hv, field.name, field.default_value, 0);
            if (!ok) SvREFCNT_dec(field.default_value);
        } else if (field.required == &PL_sv_yes) {
            SV* err = newSV(0);
            sv_catpvf(err, "key '%" SVf "' is required", field.name);
            croak_sv(err);
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




