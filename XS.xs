#define PERL_NO_GET_CONTEXT

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;
static int unstolen = 0;

#include "xs/compat.h"
#include "ppport.h"

#include "xs/types.h"
#include "xs/accessor_impl.h"
#include "xs/installer.h"

static void
CAIXS_install_inherited_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb, bool is_readonly = false) {
    shared_keys* payload;
    bool need_cb = read_cb && write_cb;

    if (need_cb) {
        assert(pkg_key != NULL);
        payload = CAIXS_install_accessor<InheritedCb, false>(aTHX_ full_name);

    } else if (pkg_key != NULL) {
        if (is_readonly) {
            payload = CAIXS_install_accessor<Inherited, true>(aTHX_ full_name);
        } else {
            payload = CAIXS_install_accessor<Inherited, false>(aTHX_ full_name);
        }

    } else {
        if (is_readonly) {
            payload = CAIXS_install_accessor<ObjectOnly, true>(aTHX_ full_name);
        } else {
            payload = CAIXS_install_accessor<ObjectOnly, false>(aTHX_ full_name);
        }
    }

    STRLEN len;
    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);
    payload->hash_key = s_hash_key;

    if (pkg_key != NULL) {
        const char* pkg_key_buf = SvPV_const(pkg_key, len);
        SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);
        payload->pkg_key = s_pkg_key;
    }

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
CAIXS_install_class_accessor(pTHX_ SV* full_name, bool is_varclass, bool is_readonly = false) {
    shared_keys* payload;

    if (is_readonly) {
        payload = CAIXS_install_accessor<PrivateClass, true>(aTHX_ full_name);
    } else {
        payload = CAIXS_install_accessor<PrivateClass, false>(aTHX_ full_name);
    }

    if (is_varclass) {
        GV* gv = gv_fetchsv(full_name, GV_ADD, SVt_PV);
        assert(gv);

        payload->storage = GvSV(gv);
        assert(payload->storage);

        /* We take ownership of this glob slot, so if someone changes the glob - they're in trouble */
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

void _unstolen_count()
PPCODE:
{
    XSRETURN_IV(unstolen);
}

void
install_object_accessor(SV* full_name, SV* hash_key)
PPCODE:
{
    CAIXS_install_inherited_accessor(aTHX_ full_name, hash_key, NULL, NULL, NULL);
    XSRETURN_UNDEF;
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

void
install_constructor(SV* full_name)
PPCODE:
{
    CAIXS_install_cv<Constructor, false>(aTHX_ full_name);
    XSRETURN_UNDEF;
}

