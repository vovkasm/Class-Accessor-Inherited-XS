#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_mg_findext
#include "ppport.h"

#include "xs/compat.h"

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;

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
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);

    AV* keys_av = newAV();
    /*
        This is a pristine AV, so skip as much checks as possible on whichever perls we can grab it.
    */
    av_extend_guts(keys_av, 1, &AvMAX(keys_av), &AvALLOC(keys_av), &AvARRAY(keys_av));
    SV** keys_array = AvARRAY(keys_av);
    keys_array[0] = s_hash_key;
    keys_array[1] = s_pkg_key;
    AvFILLp(keys_av) = 1;

#ifndef MULTIPLICITY
    CvXSUBANY(cv).any_ptr = (void*)keys_array;
#endif

    sv_magicext((SV*)cv, (SV*)keys_av, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)keys_av);
    SvRMAGICAL_off((SV*)cv);
}

OP *
CAIXS_entersub(pTHX) {
    dSP;

    CV* sv = (CV*)TOPs;
    if (sv && (SvTYPE(sv) == SVt_PVCV) && (CvXSUB(sv) == CAIXS_inherited_accessor)) {
        /*
            Assert against future XPVCV layout change - as for now, xcv_xsub shares space with xcv_root
            which are both pointers, so address check is enough, and there's no need to look into op_flags for CvISXSUB.
        */
        assert(CvISXSUB(sv));

        POPs; PUTBACK;
        CAIXS_inherited_accessor(aTHX_ sv);
        return NORMAL;
    } else {
        PL_op->op_ppaddr = PL_ppaddr[OP_ENTERSUB];
        return PL_ppaddr[OP_ENTERSUB](aTHX);
    }
}

XS(CAIXS_inherited_accessor)
{
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    /*
        Check whether we can replace opcode executor with our own variant. Unfortunatelly, this guards
        only against local changes, not when someone steals PL_ppaddr[OP_ENTERSUB] globally.
        Sorry, Devel::NYTProf.
    */
    OP* op = PL_op;
    if ((op->op_spare & 1) != 1 && op->op_ppaddr == PL_ppaddr[OP_ENTERSUB] && optimize_entersub) {
        op->op_spare |= 1;
        op->op_ppaddr = CAIXS_entersub;
    }

    shared_keys* keys;
#ifndef MULTIPLICITY
    /* Blessed are ye and get a fastpath */
    keys = (shared_keys*)(CvXSUBANY(cv).any_ptr);
    if (!keys) croak("Can't find hash key information");
#else
    /*
        We can't look into CvXSUBANY under threads, as it would have been written in the parent thread
        and might go away at any time without prior notice. So, instead, we have to scan our magical 
        refcnt storage - there's always a proper thread-local SV*, cloned for us by perl itself.
    */
    MAGIC* mg = mg_findext((SV*)cv, PERL_MAGIC_ext, &sv_payload_marker);
    if (!mg) croak("Can't find hash key information");

    keys = (shared_keys*)AvARRAY((AV*)(mg->mg_obj));
#endif

    SV* self = ST(0);
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

    /* Couldn't find value in object, so initiate a package lookup. */

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
        hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0);
        GV* glob = hent ? (GV*)HeVAL(hent) : NULL;
        if (!glob || !isGV(glob) || SvFAKE(glob)) {
            if (!glob) glob = (GV*)newSV(0);

            gv_init_sv(glob, stash, keys->pkg_key, 0);

            if (hent) {
                /* there was just a stub instead of a full glob */
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

    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in 'mro_get_linear_isa' list is a 'stash' itself.
        It's already been tested, so ajust counter and iterator to skip over it.
    */
    SSize_t fill     = AvFILLp(supers);
    SV** supers_list = AvARRAY(supers);

    SV* elem;
    while (--fill >= 0) {
        elem = *(++supers_list);

        if (elem) {
            stash = gv_stashsv(elem, 0);
            TRY_FETCH_PKG_VALUE(stash, keys, hent);
        }
    }

    XSRETURN_UNDEF;
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
    CAIXS_install_accessor(aTHX_ full_name, hash_key, pkg_key);
    XSRETURN_UNDEF;
}

