#define PERL_NO_GET_CONTEXT

extern "C" {
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
}

#define NEED_mg_findext
#include "ppport.h"

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;

#include "xs/compat.h"
#include "xs/accessor_impl.h"

static void
CAIXS_install_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb)
{
    STRLEN len;

    const char* full_name_buf = SvPV_nolen(full_name);
    bool need_cb = read_cb && write_cb;

    CV* cv;
    if (need_cb) {
        cv = newXS_flags(full_name_buf, &CAIXS_inherited_accessor<true>, __FILE__, NULL, SvUTF8(full_name));
    } else {
        cv = newXS_flags(full_name_buf, &CAIXS_inherited_accessor<false>, __FILE__, NULL, SvUTF8(full_name));
    }
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);

    AV* keys_av = newAV();
    /*
        This is a pristine AV, so skip as much checks as possible on whichever perls we can grab it.
    */
    av_extend_guts(keys_av, 3, &AvMAX(keys_av), &AvALLOC(keys_av), &AvARRAY(keys_av));
    SV** keys_array = AvARRAY(keys_av);
    keys_array[0] = s_hash_key;
    keys_array[1] = s_pkg_key;
    keys_array[2] = SvREFCNT_inc(read_cb);
    keys_array[3] = SvREFCNT_inc(write_cb);
    AvFILLp(keys_av) = 3;

#ifndef MULTIPLICITY
    CvXSUBANY(cv).any_ptr = (void*)keys_array;
#endif

    sv_magicext((SV*)cv, (SV*)keys_av, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)keys_av);
    SvRMAGICAL_off((SV*)cv);
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
    CAIXS_install_accessor(aTHX_ full_name, hash_key, pkg_key, NULL, NULL);
    XSRETURN_UNDEF;
}

void
install_inherited_cb_accessor(SV* full_name, SV* hash_key, SV* pkg_key, SV* read_cb, SV* write_cb)
PPCODE:
{
    CAIXS_install_accessor(aTHX_ full_name, hash_key, pkg_key, read_cb, write_cb);
    XSRETURN_UNDEF;
}

