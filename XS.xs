#define PERL_NO_GET_CONTEXT

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;

#include "xs/compat.h"
#include "ppport.h"
#include "xs/accessor_impl.h"

inline void
CAIXS_payload_attach(pTHX_ CV* cv, AV* keys_av) {
#ifndef MULTIPLICITY
    CvXSUBANY(cv).any_ptr = (void*)AvARRAY(keys_av);
#endif

    sv_magicext((SV*)cv, (SV*)keys_av, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)keys_av);
    SvRMAGICAL_off((SV*)cv);
}

static void
CAIXS_install_inherited_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb) {
    STRLEN len;

    const char* full_name_buf = SvPV_nolen(full_name);
    bool need_cb = read_cb && write_cb;

    CV* cv;
    if (need_cb) {
        cv = newXS_flags(full_name_buf, &CAIXS_accessor<InheritedCb>, __FILE__, NULL, SvUTF8(full_name));
    } else {
        cv = newXS_flags(full_name_buf, &CAIXS_accessor<Inherited>, __FILE__, NULL, SvUTF8(full_name));
    }
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);

    AV* keys_av = newAV();
    av_extend(keys_av, 3);
    SV** keys_array = AvARRAY(keys_av);
    keys_array[0] = s_hash_key;
    keys_array[1] = s_pkg_key;
    if (need_cb) {
        if (SvROK(read_cb) && SvTYPE(SvRV(read_cb)) == SVt_PVCV) {
            keys_array[2] = SvREFCNT_inc_NN(SvRV(read_cb));
        } else {
            keys_array[2] = NULL;
        }
        if (SvROK(write_cb) && SvTYPE(SvRV(write_cb)) == SVt_PVCV) {
            keys_array[3] = SvREFCNT_inc_NN(SvRV(write_cb));
        } else {
            keys_array[3] = NULL;
        }
    }
    AvFILLp(keys_av) = 3;

    CAIXS_payload_attach(aTHX_ cv, keys_av);
}

static void
CAIXS_install_class_accessor(pTHX_ SV* full_name, bool is_varclass) {
    const char* full_name_buf = SvPV_nolen(full_name);
    CV* cv = newXS_flags(full_name_buf, &CAIXS_accessor<PrivateClass>, __FILE__, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    AV* keys_av = newAV();
    av_extend(keys_av, 1);
    SV** keys_array = AvARRAY(keys_av);
    if (is_varclass) {
        keys_array[0] = get_sv(full_name_buf, GV_ADD);
        SvREFCNT_inc_simple_void_NN(keys_array[0]);
    } else {
        keys_array[0] = newSV(0);
    }
    AvFILLp(keys_av) = 0;

    CAIXS_payload_attach(aTHX_ cv, keys_av);
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

BOOT:
{
    SV** check_env = hv_fetch(GvHV(PL_envgv), "CAIXS_DISABLE_ENTERSUB", 22, 0);
    if (check_env && SvTRUE(*check_env)) optimize_entersub = 0;
}

void
install_inherited_accessor(SV* full_name, SV* hash_key, SV* pkg_key)
PPCODE: 
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, pkg_key, NULL, NULL);
    XSRETURN_UNDEF;
}

void
install_inherited_cb_accessor(SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb)
PPCODE:
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, pkg_key, read_cb, write_cb);
    XSRETURN_UNDEF;
}

void
install_class_accessor(SV* full_name, SV* is_varclass)
PPCODE:
{
    CAIXS_install_class_accessor(aTHX_ full_name, SvTRUE(is_varclass));
    XSRETURN_UNDEF;
}

