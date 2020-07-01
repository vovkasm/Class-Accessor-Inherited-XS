#include "xs/meta.h"
#include <new>

namespace caixs { namespace meta {

static MGVTBL package_marker;
static MGVTBL field_marker;

static int package_meta_free(pTHX_ SV*, MAGIC* mg);
static int field_meta_free(pTHX_ SV*, MAGIC* mg);

void init_meta() {
    package_marker.svt_free = &package_meta_free;
    field_marker.svt_free = &field_meta_free;
}

static void attach_magic(SV* sv, MGVTBL* marker, void* value) {
    MAGIC* mg;
    Newx(mg, 1, MAGIC);
    mg->mg_moremagic = SvMAGIC(sv);
    mg->mg_virtual = marker;
    mg->mg_type = PERL_MAGIC_ext;
    mg->mg_len = 0;
    mg->mg_ptr = (char*)value;
    mg->mg_private = 0;
    mg->mg_obj = NULL;
    mg->mg_flags = 0;

    SvMAGIC_set(sv, mg);
    //SvRMAGICAL_off(sv); ???
}

static int package_meta_free(pTHX_ SV*, MAGIC* mg) {
    if (mg->mg_virtual == &package_marker) {
        PackageMeta* meta = (PackageMeta*)mg->mg_ptr;
        meta->~PackageMeta();
    }
    return 0;
}

static int field_meta_free(pTHX_ SV*, MAGIC* mg) {
    if (mg->mg_virtual == &field_marker) {
        FieldMeta* meta = (FieldMeta*)mg->mg_ptr;
        meta->~FieldMeta();
    }
    return 0;
}

static void* find_magic(SV* sv, MGVTBL* marker) {
    if (SvTYPE(sv) >= SVt_PVMG) {
        for (MAGIC* mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic) {
            if (mg->mg_virtual == marker) {
                return mg->mg_ptr;
            }
        }
    }
    return NULL;
}

PackageMeta* find_package(HV* stash) { return (PackageMeta*)find_magic((SV*)stash, &package_marker); }
FieldMeta*   find_field(SV* field)   { return (FieldMeta*)  find_magic(field,      &field_marker);   }

static PackageMeta* create_package(HV* stash) {
    if (SvREADONLY(stash)) return NULL;
    if ((SvTYPE(stash) > SVt_PVMG) && SvOK(stash)) return NULL;

    char* storage = (char*) malloc(sizeof(PackageMeta));
    PackageMeta* meta = new(storage) PackageMeta();

    SvUPGRADE((SV*)stash, SVt_PVMG);
    attach_magic((SV*)stash, &package_marker, meta);
    return meta;
}

// field meta
FieldMeta::FieldMeta(): name(NULL), required{false}, default_value{NULL} { }

FieldMeta::FieldMeta(SV* name_, bool required_, SV* default_value_) {
    name = SvREFCNT_inc_simple(name_);
    required = required_;
    if (default_value_ && SvOK(default_value_)) {
        default_value = SvREFCNT_inc_simple(default_value_);
    }
}

FieldMeta::~FieldMeta() {
    if (name)          { SvREFCNT_dec(name); }
    if (default_value) { SvREFCNT_dec(default_value); }
}

void FieldMeta::activate(HV* obj) {
    STRLEN f_len;
    const char* f_name = SvPV(name, f_len);

    if (required) {
        SV** ref = hv_fetch(obj, f_name, f_len, 0);
        if (!ref) croak("key '%s' is required", f_name);
        return;
    }

    if (default_value && !hv_exists(obj, f_name, f_len)) {
        SV* val = SvREFCNT_inc(default_value);
        SV** ret = hv_store(obj, f_name, f_len, val, 0);
        if (!ret) SvREFCNT_dec(val);
    }
}

// package meta
PackageMeta::PackageMeta() : fields(newHV()) {}

PackageMeta::~PackageMeta() {
    SvREFCNT_dec(fields);
}

void PackageMeta::record(SV* hash_key, bool required, SV* default_value) {
    if (!hash_key) return;
    if (!(SvTYPE(hash_key) <= SVt_PVMG) && SvROK(hash_key)) return;

    STRLEN k_len;
    const char* k_name = SvPV(hash_key, k_len);

    SV** ref = hv_fetch(fields, k_name, k_len, 0);
    if (ref) return;

    SV* field_sv = newSV(0);
    SvUPGRADE(field_sv, SVt_PVMG);

    char* storage = (char*) malloc(sizeof(FieldMeta));
    FieldMeta* field = new(storage) FieldMeta(hash_key, required, default_value);
    attach_magic(field_sv, &field_marker, field);

    SV** ret = hv_store(fields, k_name, k_len, field_sv, 0);
    if (!ret) SvREFCNT_dec_NN(field_sv);
}

void PackageMeta::activate(SV *sv) {
    if (!(sv && SvROK(sv))) return;

    SV* obj = SvRV(sv);
    if (SvTYPE(obj) != SVt_PVHV) return;
    if (!SvOBJECT(obj)) return;

    HV* hv   = (HV*)obj;
    HE** arr = HvARRAY(fields);
    HE** end = arr + HvMAX(fields) + 1;
    HE* cur  = nullptr;

    while(true) {
        if (cur) { cur = HeNEXT(cur); }
        else     {  while (!cur && arr != end) cur = *arr++; }

        if (!cur) break;

        SV* field_sv = HeVAL(cur);
        FieldMeta* field = find_field(field_sv);
        if (!field) continue;

        field->activate(hv);
    }
}

// API-helpers

void install (SV* full_name, SV* hash_key, bool required, SV *default_value) {
    STRLEN len;

    const char* name = SvPV_const(full_name, len);

    CV* cv = get_cvn_flags(name, len, 0);
    if (!cv) return;

    GV* gv = CvGV(cv);
    if (!gv) return;

    HV* stash = GvSTASH(gv);
    if (!stash) return;

    PackageMeta* meta = find_package(stash);
    if (!meta) meta = create_package(stash);
    if (!meta) return;

    meta->record(hash_key, required, default_value);
}

void activate(HV* stash, SV* object) {
    PackageMeta* meta = find_package(stash);
    if (!meta) return;

    meta->activate(object);
}



}}




