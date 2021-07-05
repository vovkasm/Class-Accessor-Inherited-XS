#define PERL_NO_GET_CONTEXT

#ifdef __cplusplus
extern "C++" {
#include <algorithm>
}
#endif

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;
static int unstolen = 0;

#include "xs/meta.h"
#include "xs/compat.h"
#include "xs/types.h"
#include "xs/accessors.h"
#include "xs/installer.h"

static void
CAIXS_install_inherited_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb, int opts) {
    install_info info;
    bool need_cb = read_cb && write_cb;

    if (need_cb) {
        assert(pkg_key != NULL);

        if (opts & IsNamed) {
            info = CAIXS_install_accessor<InheritedCbNamed>(aTHX_ full_name, (AccessorOpts)(opts & ~IsNamed));
        } else {
            info = CAIXS_install_accessor<InheritedCb>(aTHX_ full_name, (AccessorOpts)opts);
        }

    } else if (pkg_key != NULL) {
        info = CAIXS_install_accessor<Inherited>(aTHX_ full_name, (AccessorOpts)opts);

    } else {
        info = CAIXS_install_accessor<ObjectOnly>(aTHX_ full_name, (AccessorOpts)opts);
        /*
        SV* required = &PL_sv_yes;
        SV* default_val = &PL_sv_undef;
        caixs::meta::install(info.cv, hash_key, required, default_val);
        */
    }

    STRLEN len;
    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);
    info.payload->hash_key = s_hash_key;

    if (pkg_key != NULL) {
        const char* pkg_key_buf = SvPV_const(pkg_key, len);
        SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);
        info.payload->pkg_key = s_pkg_key;
    }

    if (need_cb) {
        if (SvROK(read_cb) && SvTYPE(SvRV(read_cb)) == SVt_PVCV) {
            info.payload->read_cb = SvREFCNT_inc_NN(SvRV(read_cb));
        } else {
            info.payload->read_cb = NULL;
        }

        if (SvROK(write_cb) && SvTYPE(SvRV(write_cb)) == SVt_PVCV) {
            info.payload->write_cb = SvREFCNT_inc_NN(SvRV(write_cb));
        } else {
            info.payload->write_cb = NULL;
        }
    }
}

static void
CAIXS_install_class_accessor(pTHX_ SV* full_name, SV* default_sv, bool is_varclass, int opts) {
    bool is_lazy = SvROK(default_sv) && SvTYPE(SvRV(default_sv)) == SVt_PVCV;

    install_info info;
    if (is_lazy) {
        info = CAIXS_install_accessor<LazyClass>(aTHX_ full_name, (AccessorOpts)opts);

    } else {
        info = CAIXS_install_accessor<PrivateClass>(aTHX_ full_name, (AccessorOpts)opts);
    }

    if (is_varclass) {
        GV* gv = gv_fetchsv(full_name, GV_ADD, SVt_PV);
        assert(gv);

        info.payload->storage = GvSV(gv);
        assert(info.payload->storage);

        /* We take ownership of this glob slot, so if someone changes the glob - they're in trouble */
        SvREFCNT_inc_simple_void_NN(info.payload->storage);

    } else {
        info.payload->storage = newSV(0);
    }

    if (SvOK(default_sv)) {
        if (is_lazy) {
            info.payload->lazy_cb = SvREFCNT_inc_NN(SvRV(default_sv));

        } else {
            sv_setsv(info.payload->storage, default_sv);
        }
    }
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

BOOT:
{
    SV** check_env = hv_fetch(GvHV(PL_envgv), "CAIXS_DISABLE_ENTERSUB", 22, 0);
    if (check_env && SvTRUE(*check_env)) optimize_entersub = 0;
#ifdef CAIX_OPTIMIZE_OPMETHOD
    MUTEX_LOCK(&PL_my_ctx_mutex);
    qsort(accessor_map, ACCESSOR_MAP_SIZE, sizeof(accessor_cb_pair_t), CAIXS_map_compare);
    MUTEX_UNLOCK(&PL_my_ctx_mutex);
#endif
    HV* stash = gv_stashpv("Class::Accessor::Inherited::XS", 0);
    newCONSTSUB(stash, "BINARY_UNSAFE", CAIX_BINARY_UNSAFE_RESULT);
    newCONSTSUB(stash, "OPTIMIZED_OPMETHOD", CAIX_OPTIMIZE_OPMETHOD_RESULT);
}

void
install_object_accessor(SV* full_name, SV* hash_key, int opts)
PPCODE:
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, NULL, NULL, NULL, opts);
    XSRETURN_UNDEF;
}

void
install_inherited_accessor(SV* full_name, SV* hash_key, SV* pkg_key, int opts)
PPCODE: 
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, pkg_key, NULL, NULL, opts);
    XSRETURN_UNDEF;
}

void
install_inherited_cb_accessor(SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb, int opts)
PPCODE:
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, pkg_key, read_cb, write_cb, opts);
    XSRETURN_UNDEF;
}

void
install_class_accessor(SV* full_name, SV* default_sv, SV* is_varclass, SV* opts)
PPCODE:
{
    CAIXS_install_class_accessor(aTHX_ full_name, default_sv, SvTRUE(is_varclass), SvIV(opts));
    XSRETURN_UNDEF;
}

void
install_constructor(SV* full_name)
PPCODE:
{
    CAIXS_install_cv<Constructor, None>(aTHX_ full_name);
    XSRETURN_UNDEF;
}

void
test_install_meta(SV* full_name, SV* hash_key, SV* required, SV* default_value)
PPCODE:
{
    STRLEN len;
    const char* name = SvPV_const(full_name, len);
    CV* cv = get_cvn_flags(name, len, SVf_UTF8);
    if (!cv) croak("Can't get cv");

    caixs::meta::install(cv, hash_key, required, default_value);
    XSRETURN_UNDEF;
}

MODULE = Class::Accessor::Inherited::XS     PACKAGE = Class::Accessor::Inherited::XS::Constants
PROTOTYPES: DISABLE

BOOT:
{
    HV* stash = gv_stashpv("Class::Accessor::Inherited::XS::Constants", GV_ADD);
    AV* exp = get_av("Class::Accessor::Inherited::XS::Constants::EXPORT", GV_ADD);
#define RGSTR(c) \
    newCONSTSUB(stash, #c , newSViv(c)); \
    av_push(exp, newSVpvn(#c, strlen(#c)));
    RGSTR(None);
    RGSTR(IsReadonly);
    RGSTR(IsWeak);
    RGSTR(IsNamed);

    AV* isa = get_av("Class::Accessor::Inherited::XS::Constants::ISA", GV_ADD);
    av_push(isa, newSVpvs("Exporter"));

    hv_stores(get_hv("INC", GV_ADD), "Class/Accessor/Inherited/XS/Constants.pm", &PL_sv_yes);
}

MODULE = Class::Accessor::Inherited::XS     PACKAGE = Class::Accessor::Inherited::XS::Debug
PROTOTYPES: DISABLE

void unstolen_count()
PPCODE:
{
    XSRETURN_IV(unstolen);
}
