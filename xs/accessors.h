#ifndef __INHERITED_XS_IMPL_H_
#define __INHERITED_XS_IMPL_H_

#include "fimpl.h"
#include "util.h"
#include "op.h"

/*
    These macroses impose the following rules:
        - SP is at the start of the args list
        - SP may become invalid afterwards, so don't touch it
        - PL_stack_sp is updated when needed

    The latter may be not that obvious, but it's a result of a callback doing
    dirty stack work for us. Note that only essential cleanup is done
    after call_sv().
*/

#define CALL_READ_CB(result)                        \
    if (type == InheritedCb && payload->read_cb) {  \
        ENTER;                                      \
        PUSHMARK(SP);                               \
        *(SP+1) = result;                           \
        call_sv(payload->read_cb, G_SCALAR);        \
        LEAVE;                                      \
    } else {                                        \
        *(SP+1) = result;                           \
    }                                               \

#define CALL_WRITE_CB(slot, need_alloc)             \
    if (type == InheritedCb && payload->write_cb) { \
        ENTER;                                      \
        PUSHMARK(SP);                               \
        call_sv(payload->write_cb, G_SCALAR);       \
        SPAGAIN;                                    \
        LEAVE;                                      \
        if (need_alloc) slot = newSV(0);            \
        sv_setsv(slot, *SP);                        \
        *SP = slot;                                 \
    } else {                                        \
        if (need_alloc) slot = newSV(0);            \
        sv_setsv(slot, *(SP+2));                    \
        PUSHs(slot);                                \
        PUTBACK;                                    \
    }                                               \

#define READONLY_TYPE_ASSERT \
    assert(type == Inherited || type == PrivateClass || type == ObjectOnly || type == LazyClass)

#define READONLY_CROAK_CHECK                            \
    if (type != InheritedCb && is_readonly) {           \
        READONLY_TYPE_ASSERT;                           \
        croak("Can't set value in readonly accessor");  \
        return;                                         \
    }                                                   \

template <AccessorType type, bool is_readonly> static
void
CAIXS_inherited_compat(pTHX_ SV** SP, HV* stash, shared_keys* payload, int items) {
    if (items > 1) {
        READONLY_CROAK_CHECK;

        GV* glob = CAIXS_fetch_glob(aTHX_ stash, payload->pkg_key);
        SV* new_value = GvSVn(glob);
        CALL_WRITE_CB(new_value, 0);

        return;
    }

    #define TRY_FETCH_PKG_VALUE(stash, payload, hent)                   \
    if (stash && (hent = hv_fetch_ent(stash, payload->pkg_key, 0, 0))) {\
        SV* sv = GvSV(HeVAL(hent));                                     \
        if (sv && SvOK(sv)) {                                           \
            CALL_READ_CB(sv);                                           \
            return;                                                     \
        }                                                               \
    }

    HE* hent;
    TRY_FETCH_PKG_VALUE(stash, payload, hent);

    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in the 'mro_get_linear_isa' list is the 'stash' itself.
        It's already been tested, so ajust both counter and iterator to skip over it.
    */
    SSize_t fill     = AvFILLp(supers);
    SV** supers_list = AvARRAY(supers);

    SV* elem;
    while (--fill >= 0) {
        elem = *(++supers_list);

        if (elem) {
            stash = gv_stashsv(elem, 0);
            TRY_FETCH_PKG_VALUE(stash, payload, hent);
        }
    }

    /* XSRETURN_UNDEF */
    CALL_READ_CB(&PL_sv_undef);
    return;
}

inline SV*
CAIXS_inherited_cache(pTHX_ HV* stash, GV* glob, shared_keys* payload) {
    const struct mro_meta* stash_meta = HvMROMETA(stash);
    const int64_t curgen = (int64_t)PL_sub_generation + stash_meta->pkg_gen;

    if (GvLINE(glob) == curgen || GvGPFLAGS(glob)) return GvSV(glob);
    if (UNLIKELY(curgen > ((U32)1 << 31) - 1)) {
        warn("MRO cache generation 31 bit wraparound");
        PL_sub_generation = 0;
    }

    return NULL;
}

inline SV*
CAIXS_update_cache(pTHX_ HV* stash, GV* glob, shared_keys* payload) {
    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in the 'mro_get_linear_isa' list is the 'stash' itself.
        It's already been tested, so ajust both counter and iterator to skip over it.
    */
    SSize_t fill     = AvFILLp(supers);
    SV** supers_list = AvARRAY(supers);

    SV* elem;
    HE* hent;
    SV* result = NULL;

    GV* stack[fill + 1];
    stack[fill] = glob;

    while (result == NULL && --fill >= 0) {
        elem = *(++supers_list);

        if (elem) {
            HV* next_stash = gv_stashsv(elem, GV_ADD); /* inherited from empty stash */
            GV* next_gv = CAIXS_fetch_glob(aTHX_ next_stash, payload->pkg_key);
            stack[fill] = next_gv;

            result = CAIXS_inherited_cache(aTHX_ next_stash, next_gv, payload);
        }
    }

    if (!result) result = GvSVn(stack[0]); /* undef from root */

    for (int i = fill + 1; i <= AvFILLp(supers); ++i) {
        GV* cur_gv = stack[i];

        const struct mro_meta* stash_meta = HvMROMETA(GvSTASH(cur_gv));
        const U32 curgen = PL_sub_generation + stash_meta->pkg_gen;
        GvLINE(cur_gv) = curgen & (((U32)1 << 31) - 1); /* perl may lack 'gp_flags' field, so we must care about the highest bit */

        SV** sv_slot = &GvSV(cur_gv);

        SvREFCNT_inc_simple_NN(result);
        SvREFCNT_dec(*sv_slot);
        *sv_slot = result;
    }

    return result;
}

template <bool is_readonly>
struct FImpl<Constructor, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;

    CAIXS_install_entersub<Constructor, is_readonly>(aTHX);
    if (UNLIKELY(!items)) croak("Usage: $obj->constructor or __PACKAGE__->constructor");

    PL_stack_sp = ++MARK; /* PUTBACK */

    if (!stash) stash = CAIXS_find_stash(aTHX_ *MARK, cv);
    SV** ret = MARK++;

    SV* self;
    if (items == 2 && SvROK(*MARK) && SvTYPE(SvRV(*MARK)) == SVt_PVHV) {
        self = *MARK;

    } else if ((items & 1) == 0) {
        croak("Odd number of elements in hash constructor");

    } else {
        HV* hash = newHV();

        while (MARK < SP) {
            SV* key = *MARK++;
            /* Don't bother with retval here, as in pp_anonhash */
            hv_store_ent(hash, key, newSVsv(*MARK++), 0);
        }

        self = sv_2mortal(newRV_noinc((SV*)hash));
    }

    sv_bless(self, stash);
    *ret = self;
    return;
}};

template <bool is_readonly>
struct FImpl<LazyClass, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");
    shared_keys* payload = CAIXS_find_payload(cv);

    if (items > 1) {
        const int type = LazyClass; /* for READONLY_CROAK_CHECK */
        READONLY_CROAK_CHECK;

        PUSHMARK(SP - items); /* our dAXMARK has popped one */
        FImpl<PrivateClass, is_readonly>::CAIXS_accessor(aTHX_ SP, cv, stash);

    } else {
        ENTER;
        PUSHMARK(--SP); /* SP -= items */
        call_sv(payload->lazy_cb, G_SCALAR);
        SPAGAIN;
        LEAVE;

        sv_setsv(payload->storage, *SP);
        *SP = payload->storage;
    }

    CvXSUB(cv) = (XSUBADDR_t)&CAIXS_entersub_wrapper<PrivateClass, is_readonly>;
    SvREFCNT_dec_NN(payload->lazy_cb);
    payload->lazy_cb = NULL;

    return;
}};

template <bool is_readonly>
struct FImpl<PrivateClass, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<PrivateClass, is_readonly>(aTHX);
    shared_keys* payload = CAIXS_find_payload(cv);

    const int type = PrivateClass; /* for CALL_*_CB */

    if (items == 1) {
        CALL_READ_CB(payload->storage);
        return;
    }

    READONLY_CROAK_CHECK;
    CALL_WRITE_CB(payload->storage, 0);
    return;
}};

/* covers type = {Inherited, InheritedCb, ObjectOnly} */
template <AccessorType type, bool is_readonly>
struct FImpl {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<type, is_readonly>(aTHX);
    shared_keys* payload = CAIXS_find_payload(cv);

    SV* self = *(SP+1);
    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (UNLIKELY(SvTYPE((SV*)obj) != SVt_PVHV)) {
            croak("Inherited accessors work only with hash-based objects");
        }

        if (items > 1) {
            READONLY_CROAK_CHECK;

            SV* new_value;
            CALL_WRITE_CB(new_value, 1);
            if (UNLIKELY(!hv_store_ent(obj, payload->hash_key, new_value, 0))) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            return;
                    
        } else {
            HE* hent = hv_fetch_ent(obj, payload->hash_key, 0, 0);
            if (hent) {
                CALL_READ_CB(HeVAL(hent));
                return;

            } else if (type == ObjectOnly) {
                CALL_READ_CB(&PL_sv_undef);
                return;
            }
        }
    }

    if (type == ObjectOnly) {
        croak("Can't use object accessor on non-object");
        return; /* gcc detects unreachability even with bare croak(), but it won't hurt */
    }

    /* Couldn't find value in the object, so initiate a package lookup. */

    if (!stash) stash = CAIXS_find_stash(aTHX_ self, cv);

    if (items > 1) {
        READONLY_CROAK_CHECK;

        GV* glob = CAIXS_fetch_glob(aTHX_ stash, payload->pkg_key);
        SV* new_value = GvSVn(glob);

        if (!GvGPFLAGS(glob)) {
            SV** svp = hv_fetchhek(PL_isarev, HvENAME_HEK(stash));
            if (svp) {
                HV* isarev = (HV*)*svp;
                hv_iterinit(isarev);

                HE* iter;
                while ((iter = hv_iternext(isarev))) {
                    HV* revstash = gv_stashsv(hv_iterkeysv(iter), GV_ADD);
                    GV* revglob = CAIXS_fetch_glob(aTHX_ revstash, payload->pkg_key);

                    if (GvSV(revglob) == new_value) GvLINE(revglob) = 0;
                }
            }

            SvREFCNT_dec(new_value);

            GvSV(glob) = newSV(0);
            new_value = GvSV(glob);
        }

        CALL_WRITE_CB(new_value, 0);

        if (SvOK(new_value)) {
            GvGPFLAGS_on(glob);

        } else {
            GvGPFLAGS_off(glob);
            GvLINE(glob) = 0;
        }

        return;
    }

    GV* glob = CAIXS_fetch_glob(aTHX_ stash, payload->pkg_key);
    SV* result = CAIXS_inherited_cache(aTHX_ stash, glob, payload);
    if (!result) result = CAIXS_update_cache(aTHX_ stash, glob, payload);

    CALL_READ_CB(result);
    return;
}};

#endif /* __INHERITED_XS_IMPL_H_ */
