#define PERL_NO_GET_CONTEXT

extern "C" {
    #include "EXTERN.h"
    #include "perl.h"
    #include "XSUB.h"
}
#include "ppport.h"
#include "xs/compat.h"
#include "xs/double_hek.h"

MGVTBL sv_payload_marker;

XS(CAIXS_inherited_accessor);

static void
CAIXS_install_accessor(pTHX_ SV* full_name, SV* hash_key)
{
    STRLEN len;

    const char* full_name_buf = SvPV_nolen(full_name);
    CV* cv = newXS_flags(full_name_buf, CAIXS_inherited_accessor, __FILE__, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV(hash_key, len);
    SV* keysv = newSV(sizeof(double_hek) + len);
    double_hek* hent = (double_hek*)SvPVX(keysv);

    HEK_LEN(hent) = len;
    memcpy(HEK_PKG_KEY(hent), CAIXS_PKG_PREFIX, sizeof(CAIXS_PKG_PREFIX) - 1);
    memcpy(HEK_KEY(hent), hash_key_buf, len + 1);
    PERL_HASH(HEK_HASH(hent), hash_key_buf, len);
    len += sizeof(CAIXS_PKG_PREFIX) - 1;
    PERL_HASH(HEK_PKG_HASH(hent), HEK_PKG_KEY(hent), len);

    if (SvUTF8(hash_key)) {
        HEK_FLAGS(hent) = HVhek_UTF8;
    } else {
        HEK_FLAGS(hent) = 0;
    }

    MAGIC* mg = sv_magicext((SV*)cv, keysv, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    mg->mg_flags |= MGf_REFCOUNTED;
    SvRMAGICAL_off((SV*)cv); // remove unnecessary perfomance overheat
    SvREFCNT_dec_NN(keysv); 

    CvXSUBANY(cv).any_ptr = (void*)keysv;
}

XS(CAIXS_inherited_accessor)
{
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    SV* self = ST(0);

    SV* keysv = (SV*)(CvXSUBANY(cv).any_ptr);
    if (!keysv) croak("Can't find hash key information");

    double_hek* hent = (double_hek*)SvPVX(keysv);

    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV)
            croak("Inherited accessor can work only with object instance that is hash-based");

        if (items > 1) {
            SV* orig_value = ST(1);
            SV* new_value  = newSVsv(orig_value);
            if (!hv_store_flags((HV*)SvRV(self), HEK_KEY(hent), HEK_LEN(hent), new_value, HEK_HASH(hent), HEK_UTF8(hent))) {
                croak("Can't store new hash value");
            }
            PUSHs(new_value);
            XSRETURN(1);
                    
        } else {
            SV** svp = CAIXS_FETCH_HASH_HEK(obj, hent);
            if (svp) {
                PUSHs(*svp);
                XSRETURN(1);
            }
        }
    }

    // Can't find in object, so try self package

    HV* stash;
    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));

    } else {
        GV* acc_gv = CvGV(cv);
        if (!acc_gv) croak("TODO: can't understand accessor name");
        stash = GvSTASH(acc_gv);

        const char* stash_name = HvNAME(stash);
        const char* self_name = SvPV_nolen(self);
        if (strcmp(stash_name, self_name) != 0) {
            stash = gv_stashsv(self, (items > 1) ? GV_ADD : 1);
        }
    }

    SV** svp;
    if (items > 1) {
        SV* orig_value = ST(1);

        //SV* acc_fullname = newSVpvf("%s::%"SVf, HvNAME(stash), acc);
        //CAIXS_install_accessor(aTHX_ c_acc_name, c_acc_name);

        if (!stash) {
            croak("Couldn't add stash for package setter");
        }

        svp = CAIXS_FETCH_PKG_HEK(stash, hent);
        GV* glob;
        if (!svp || !isGV(*svp) || SvFAKE(*svp)) {
            glob = svp ? (GV*)*svp : (GV*)newSV(0);

            U32 uflag = HEK_UTF8(hent) ? SVf_UTF8 : 0;
            gv_init_pvn(glob, stash, HEK_PKG_KEY(hent), HEK_PKG_LEN(hent), uflag);

            if (svp) {
                /* not sure when this can happen - remains untested */
                SvREFCNT_dec_NN(*svp);
                *svp = (SV*)glob;
                SvREFCNT_inc_simple_NN((SV*)glob);
            } else {
                hv_store_flags(stash, HEK_PKG_KEY(hent), HEK_PKG_LEN(hent), (SV*)glob, HEK_PKG_HASH(hent), HEK_UTF8(hent));
            }
        } else {
            glob = (GV*)*svp;
        }

        SV* new_value = GvSVn(glob);
        sv_setsv(new_value, orig_value);
        PUSHs(new_value);

        XSRETURN(1);
    }
    
    #define TRY_FETCH_PKG_VALUE(stash, hent, svp)               \
    if (stash && (svp = CAIXS_FETCH_PKG_HEK(stash, hent))) {    \
        SV* sv = GvSV(*svp);                                    \
        if (sv && SvOK(sv)) {                                   \
            PUSHs(sv);                                          \
            XSRETURN(1);                                        \
        }                                                       \
    }

    TRY_FETCH_PKG_VALUE(stash, hent, svp);

    // Now try all superclasses
    AV* supers = mro_get_linear_isa(stash);

    SV* elem;
    SSize_t fill = AvFILLp(supers) + 1;
    SV** supers_list = AvARRAY(supers);
    while (--fill >= 0) {
        elem = *supers_list++;

        if (elem) {
            stash = gv_stashsv(elem, 0);
            TRY_FETCH_PKG_VALUE(stash, hent, svp);
        }
    }

    XSRETURN_UNDEF;
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

void
install_inherited_accessor(SV* full_name, SV* hash_key)
PPCODE: 
{
    CAIXS_install_accessor(aTHX_ full_name, hash_key);
    XSRETURN_UNDEF;
}

