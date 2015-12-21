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

inline shared_keys*
CAIXS_payload_init(pTHX_ CV* cv, int alloc_keys) {
    AV* keys_av = newAV();

    av_extend(keys_av, alloc_keys);
    AvFILLp(keys_av) = alloc_keys;

    CAIXS_payload_attach(aTHX_ cv, keys_av);
    return (shared_keys*)AvARRAY(keys_av);
}

static void
CAIXS_install_inherited_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb) {
    STRLEN len;

    const char* full_name_buf = SvPV_const(full_name, len);
    bool need_cb = read_cb && write_cb;

#ifdef CAIX_BINARY_UNSAFE
    if (strnlen(full_name_buf, len) < len) {
        croak("Attempted to install binary accessor, but they're not supported on this perl");
    }
#endif

    CV* cv;
    if (need_cb) {
        cv = Perl_newXS_len_flags(aTHX_ full_name_buf, len, &CAIXS_entersub_wrapper<InheritedCb>, __FILE__, NULL, NULL, SvUTF8(full_name));
    } else {
        cv = Perl_newXS_len_flags(aTHX_ full_name_buf, len, &CAIXS_entersub_wrapper<Inherited>, __FILE__, NULL, NULL, SvUTF8(full_name));
    }
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);

    shared_keys* payload = CAIXS_payload_init(aTHX_ cv, 3);
    payload->hash_key = s_hash_key;
    payload->pkg_key = s_pkg_key;

    if (need_cb) {
        if (SvROK(read_cb) && SvTYPE(SvRV(read_cb)) == SVt_PVCV) {
            payload->read_cb = SvREFCNT_inc_NN(SvRV(read_cb));
        } else {
            payload->read_cb = NULL;
        }
        if (SvROK(write_cb) && SvTYPE(SvRV(write_cb)) == SVt_PVCV) {
            payload->write_cb = SvREFCNT_inc_NN(SvRV(write_cb));
        } else {
            payload->write_cb = NULL;
        }
    }
}

static void
CAIXS_install_class_accessor(pTHX_ SV* full_name, bool is_varclass) {
    const char* full_name_buf = SvPV_nolen(full_name);
    CV* cv = newXS_flags(full_name_buf, &CAIXS_entersub_wrapper<PrivateClass>, __FILE__, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    shared_keys* payload = CAIXS_payload_init(aTHX_ cv, 0);

    if (is_varclass) {
        /*
            We take ownership on this glob slot, so if someone changes the glob - they're in trouble
        */
        payload->storage = get_sv(full_name_buf, GV_ADD);
        SvREFCNT_inc_simple_void_NN(payload->storage);

    } else {
        payload->storage = newSV(0);
    }
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

BOOT:
{
    SV** check_env = hv_fetch(GvHV(PL_envgv), "CAIXS_DISABLE_ENTERSUB", 22, 0);
    if (check_env && SvTRUE(*check_env)) optimize_entersub = 0;

    HV* stash = gv_stashpv("Class::Accessor::Inherited::XS", 0);
    newCONSTSUB(stash, "BINARY_UNSAFE", CAIX_BINARY_UNSAFE_RESULT);
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

