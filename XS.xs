#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "xs/compat.h"
#include "xs/double_hek.h"

static MGVTBL sv_payload_marker;

typedef struct shared_keys {
    SV* hash_key;
    SV* pkg_key;
} shared_keys;

XS(CAIXS_inherited_accessor);

static void
CAIXS_install_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key)
{
    STRLEN len;

    const char* full_name_buf = SvPV_nolen(full_name);
    CV* cv = newXS_flags(full_name_buf, CAIXS_inherited_accessor, __FILE__, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -len : len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -len : len, 0);

    SV* keys_sv = newSV(sizeof(shared_keys));
    shared_keys* keys = (shared_keys*)SvPVX(keys_sv);
    keys->hash_key = s_hash_key;
    keys->pkg_key = s_pkg_key;
    CvXSUBANY(cv).any_ptr = (void*)keys;

    #define ATTACH_MAGIC(target, sv) STMT_START {                                           \
    MAGIC* mg = sv_magicext((SV*)target, sv, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);  \
    mg->mg_flags |= MGf_REFCOUNTED;                                                         \
    SvREFCNT_dec_NN(sv);                                                                    \
    } STMT_END

    ATTACH_MAGIC(cv, s_hash_key);
    ATTACH_MAGIC(cv, s_pkg_key);
    ATTACH_MAGIC(cv, keys_sv);

    SvRMAGICAL_off((SV*)cv);
}

XS(CAIXS_inherited_accessor)
{
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    SV* self = ST(0);

    shared_keys* keys = (shared_keys*)(CvXSUBANY(cv).any_ptr);
    if (!keys) croak("Can't find hash key information");

    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV) {
            croak("Inherited accessors can only work with object instances that is hash-based");
        }

        if (items > 1) {
            SV* new_value  = newSVsv(ST(1));
            if (!hv_store_ent(obj, keys->hash_key, new_value, 0)) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            PUSHs(new_value);
            XSRETURN(1);
                    
        } else {
            HE* hent = hv_fetch_ent(obj, keys->hash_key, 0, 0);
            if (hent) {
                PUSHs(HeVAL(hent));
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
        if (!acc_gv) croak("Can't have pkg accessor in anon sub");
        stash = GvSTASH(acc_gv);

        const char* stash_name = HvNAME(stash);
        const char* self_name = SvPV_nolen(self);
        if (strcmp(stash_name, self_name) != 0) {
            stash = gv_stashsv(self, GV_ADD);
            if (!stash) croak("Couldn't get required stash");
        }
    }

    HE* hent;
    if (items > 1) {
        //SV* acc_fullname = newSVpvf("%s::%"SVf, HvNAME(stash), acc);
        //CAIXS_install_accessor(aTHX_ c_acc_name, c_acc_name);

        hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0);
        GV* glob = hent ? (GV*)HeVAL(hent) : NULL;
        if (!glob || !isGV(glob) || SvFAKE(glob)) {
            if (!glob) glob = (GV*)newSV(0);

            gv_init_sv(glob, stash, keys->pkg_key, 0);

            if (hent) {
                /* not sure when this can happen - remains untested */
                SvREFCNT_inc_simple_NN((SV*)glob);
                SvREFCNT_dec_NN(HeVAL(hent));
                HeVAL(hent) = (SV*)glob;
            } else {
                if (!hv_store_ent(stash, keys->pkg_key, (SV*)glob, 0)) {
                    SvREFCNT_dec_NN(glob);
                    croak("Can't add a glob to package");
                }
            }
        }

        SV* new_value = GvSVn(glob);
        sv_setsv(new_value, ST(1));
        PUSHs(new_value);

        XSRETURN(1);
    }
    
    #define TRY_FETCH_PKG_VALUE(stash, keys, hent)                      \
    if (stash && (hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0))) {   \
        SV* sv = GvSV(HeVAL(hent));                                     \
        if (sv && SvOK(sv)) {                                           \
            PUSHs(sv);                                                  \
            XSRETURN(1);                                                \
        }                                                               \
    }

    TRY_FETCH_PKG_VALUE(stash, keys, hent);

    // Now try all superclasses
    AV* supers = mro_get_linear_isa(stash);

    SV* elem;
    SSize_t fill = AvFILLp(supers) + 1;
    SV** supers_list = AvARRAY(supers);
    while (--fill >= 0) {
        elem = *supers_list++;

        if (elem) {
            stash = gv_stashsv(elem, 0);
            TRY_FETCH_PKG_VALUE(stash, keys, hent);
        }
    }

    XSRETURN_UNDEF;
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

void
install_inherited_accessor(SV* full_name, SV* hash_key, SV* pkg_key)
PPCODE: 
{
    CAIXS_install_accessor(aTHX_ full_name, hash_key, pkg_key);
    XSRETURN_UNDEF;
}

