#ifndef __INHERITED_XS_IMPL_H_
#define __INHERITED_XS_IMPL_H_

/*
    These macroses impose the following rules:
        - SP is at the start of the args list
        - SP may become invalid afterwards, so don't touch it
        - PL_stack_sp is updated when needed

    The latter may be not that obvious, but it's a result of a callback doing
    dirty stack work for us. Note that only essential cleanup is done
    after call_sv().
*/

#define CALL_READ_CB(result)                    \
    if (type == InheritedCb && keys->read_cb) { \
        ENTER;                                  \
        PUSHMARK(SP);                           \
        *(SP+1) = result;                       \
        call_sv(keys->read_cb, G_SCALAR);       \
        LEAVE;                                  \
    } else {                                    \
        *(SP+1) = result;                       \
    }                                           \

#define CALL_WRITE_CB(slot, need_alloc)         \
    if (type == InheritedCb && keys->write_cb) {\
        ENTER;                                  \
        PUSHMARK(SP);                           \
        call_sv(keys->write_cb, G_SCALAR);      \
        SPAGAIN;                                \
        LEAVE;                                  \
        if (need_alloc) slot = newSV(0);        \
        sv_setsv(slot, *SP);                    \
        *SP = slot;                             \
    } else {                                    \
        if (need_alloc) slot = newSV(0);        \
        sv_setsv(slot, *(SP+2));                \
        PUSHs(slot);                            \
        PUTBACK;                                \
    }                                           \

#define OP_UNSTEAL(name) STMT_START {       \
        ++unstolen;                         \
        PL_op->op_ppaddr = PL_ppaddr[name]; \
        return PL_ppaddr[name](aTHX);       \
    } STMT_END                              \

#define READONLY_TYPE_ASSERT \
    assert(type == Inherited || type == PrivateClass || type == ObjectOnly || type == LazyClass)

#define READONLY_CROAK_CHECK                            \
    if (type != InheritedCb && is_readonly) {           \
        READONLY_TYPE_ASSERT;                           \
        croak("Can't set value in readonly accessor");  \
        return;                                         \
    }                                                   \

template <AccessorType type, bool is_readonly>
struct FImpl;

template <AccessorType type, bool is_readonly> inline
void
CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    FImpl<type, is_readonly>::CAIXS_accessor(aTHX_ SP, cv, stash);
}

template <AccessorType type, bool is_readonly> static
XSPROTO(CAIXS_entersub_wrapper) {
    dSP;

    CAIXS_accessor<type, is_readonly>(aTHX_ SP, cv, NULL);

    return;
}

#ifdef CAIX_OPTIMIZE_OPMETHOD

template <AccessorType type, int optype, bool is_readonly> static
OP *
CAIXS_opmethod_wrapper(pTHX) {
    dSP;

    SV* self = PL_stack_base + TOPMARK == SP ? (SV*)NULL : *(PL_stack_base + TOPMARK + 1);
    HV* stash = NULL;

    /*
        This block isn't required for the 'goto gotcv' case, but skipping it
        (or swapping those blocks) makes unstealing inside 'goto gotcv' block impossible,
        thus requiring additional check in the fast case, which is to be avoided.
    */
#ifndef GV_CACHE_ONLY
    if (LIKELY(self != NULL)) {
        SvGETMAGIC(self);
#else
    if (LIKELY(self && !SvGMAGICAL(self))) {
        /* SvIsCOW_shared_hash is incompatible with SvGMAGICAL, so skip it completely */
        if (SvIsCOW_shared_hash(self)) {
            stash = gv_stashsv(self, GV_CACHE_ONLY);
        } else
#endif
        if (SvROK(self)) {
            SV* ob = SvRV(self);
            if (SvOBJECT(ob)) stash = SvSTASH(ob);

        } else if (SvPOK(self)) {
            const char* packname = SvPVX_const(self);
            const STRLEN packlen = SvCUR(self);
            const int is_utf8 = SvUTF8(self);

#ifndef GV_CACHE_ONLY
            const HE* const he = (const HE *)hv_common(PL_stashcache, NULL, packname, packlen, is_utf8, 0, NULL, 0);
            if (he) stash = INT2PTR(HV*, SvIV(HeVAL(he)));
            else
#endif
            stash = gv_stashpvn(packname, packlen, is_utf8);
        }
    }

    SV* meth;
    CV* cv = NULL;
    U32 hash;

    if (optype == OP_METHOD) {
        meth = TOPs;
        if (SvROK(meth)) {
            SV* const rmeth = SvRV(meth);
            if (SvTYPE(rmeth) == SVt_PVCV) {
                cv = (CV*)rmeth;
                goto gotcv; /* We don't care about the 'stash' var here */
            }
        }

        hash = 0;

    } else if (optype == OP_METHOD_NAMED) {
        meth = cSVOPx_sv(PL_op);

#ifndef GV_CACHE_ONLY
        hash = SvSHARED_HASH(meth);
#else
        hash = 0;
#endif
    }

    /* SvTYPE check appeared only since 5.22, but execute it for all perls nevertheless */
    if (UNLIKELY(!stash || SvTYPE(stash) != SVt_PVHV)) {
        OP_UNSTEAL(optype);
    }

    HE* he; /* To allow 'goto' to jump over this */
    if ((he = hv_fetch_ent(stash, meth, 0, hash))) {
        GV* gv = (GV*)(HeVAL(he));
        if (isGV(gv) && GvCV(gv) && (!GvCVGEN(gv) || GvCVGEN(gv) == (PL_sub_generation + HvMROMETA(stash)->cache_gen))) {
            cv = GvCV(gv);
        }
    }

    if (UNLIKELY(!cv)) {
        GV* gv = gv_fetchmethod_sv_flags(stash, meth, GV_AUTOLOAD|GV_CROAK);
        assert(gv);

        cv = isGV(gv) ? GvCV(gv) : (CV*)gv;
        assert(cv);
    }

gotcv:
    if (LIKELY((CvXSUB(cv) == (XSUBADDR_t)&CAIXS_entersub_wrapper<type, is_readonly>))) {
        assert(CvISXSUB(cv));

        if (optype == OP_METHOD) {--SP; PUTBACK; }

        CAIXS_accessor<type, is_readonly>(aTHX_ SP, cv, stash);

        return PL_op->op_next->op_next;

    } else {
        /*
            We could also lift off CAIXS_entersub optimization here, but that's a one-time action,
            so let it fail on it's own
        */
        OP_UNSTEAL(optype);
    }
}

#endif /* CAIX_OPTIMIZE_OPMETHOD */

template <AccessorType type, bool is_readonly> static
OP *
CAIXS_entersub(pTHX) {
    dSP;

    CV* sv = (CV*)TOPs;

    if (LIKELY(sv != NULL)) {
        if (UNLIKELY(SvTYPE(sv) != SVt_PVCV)) {
            /* can('acc')->() or (\&acc)->()  */

            if (LIKELY(SvROK(sv))) sv = (CV*)SvRV(sv);
            if (UNLIKELY(SvTYPE(sv) != SVt_PVCV)) OP_UNSTEAL(OP_ENTERSUB);
        }

        /* Some older gcc's can't deduce correct function - have to add explicit cast  */
        if (LIKELY((CvXSUB(sv) == (XSUBADDR_t)&CAIXS_entersub_wrapper<type, is_readonly>))) {
            /*
                Assert against future XPVCV layout change - as for now, xcv_xsub shares space with xcv_root
                which are both pointers, so address check is enough, and there's no need to look into op_flags for CvISXSUB.
            */
            assert(CvISXSUB(sv));

            POPs; PUTBACK;
            CAIXS_accessor<type, is_readonly>(aTHX_ SP, sv, NULL);

            return NORMAL;
        }

    }

    OP_UNSTEAL(OP_ENTERSUB);
}

template <AccessorType type, bool is_readonly> inline
void
CAIXS_install_entersub(pTHX) {
    /*
        Check whether we can replace opcode executor with our own variant. Unfortunatelly, this guards
        only against local changes, not when someone steals PL_ppaddr[OP_ENTERSUB] globally.
        Sorry, Devel::NYTProf.
    */

    OP* op = PL_op;

    if ((op->op_spare & 1) != 1 && op->op_ppaddr == PL_ppaddr[OP_ENTERSUB] && optimize_entersub) {
        op->op_spare |= 1;
        op->op_ppaddr = &CAIXS_entersub<type, is_readonly>;

#ifdef CAIX_OPTIMIZE_OPMETHOD
        OP* methop = cUNOPx(op)->op_first;
        if (LIKELY(methop != NULL)) {   /* Such op can be created by call_sv(G_METHOD_NAMED) */
            while (methop->op_sibling) { methop = methop->op_sibling; }

            if (methop->op_next == op) {
                if (methop->op_type == OP_METHOD_NAMED && methop->op_ppaddr == PL_ppaddr[OP_METHOD_NAMED]) {
                    methop->op_ppaddr = &CAIXS_opmethod_wrapper<type, OP_METHOD_NAMED, is_readonly>;

                } else if (methop->op_type == OP_METHOD && methop->op_ppaddr == PL_ppaddr[OP_METHOD]) {
                    methop->op_ppaddr = &CAIXS_opmethod_wrapper<type, OP_METHOD, is_readonly>;
                }
            }
        }
#endif /* CAIX_OPTIMIZE_OPMETHOD */
    }
}

inline MAGIC*
CAIXS_mg_findext(SV* sv, int type, MGVTBL* vtbl) {
    MAGIC* mg;

    if (sv) {
        for (mg = SvMAGIC(sv); mg; mg = mg->mg_moremagic) {
            if (mg->mg_type == type && mg->mg_virtual == vtbl)
                return mg;
        }
    }

    return NULL;
}

inline shared_keys*
CAIXS_find_keys(CV* cv) {
    shared_keys* keys;

#ifndef MULTIPLICITY
    /* Blessed are ye and get a fastpath */
    keys = (shared_keys*)(CvXSUBANY(cv).any_ptr);
    if (UNLIKELY(!keys)) croak("Can't find hash key information");
#else
    /*
        We can't look into CvXSUBANY under threads, as it could have been written in the parent thread
        and had gone away at any time without prior notice. So, instead, we have to scan our magical
        refcnt storage - there's always a proper thread-local SV*, cloned for us by perl itself.
    */
    MAGIC* mg = CAIXS_mg_findext((SV*)cv, PERL_MAGIC_ext, &sv_payload_marker);
    if (UNLIKELY(!mg)) croak("Can't find hash key information");

    keys = (shared_keys*)AvARRAY((AV*)(mg->mg_obj));
#endif

    return keys;
}

inline HV*
CAIXS_find_stash(pTHX_ SV* self, CV* cv) {
    HV* stash;

    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));

    } else {
        GV* acc_gv = CvGV(cv);
        if (UNLIKELY(!acc_gv)) croak("Can't have package accessor in anon sub");
        stash = GvSTASH(acc_gv);

        const char* stash_name = HvNAME(stash);
        const char* self_name = SvPV_nolen(self);
        if (strcmp(stash_name, self_name) != 0) {
            stash = gv_stashsv(self, GV_ADD);
            if (UNLIKELY(!stash)) croak("Couldn't get required stash");
        }
    }

    return stash;
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
    shared_keys* keys = (shared_keys*)CAIXS_find_keys(cv);

    if (items > 1) {
        const int type = LazyClass; /* for READONLY_CROAK_CHECK */
        READONLY_CROAK_CHECK;

        PUSHMARK(SP - items); /* our dAXMARK has popped one */
        FImpl<PrivateClass, is_readonly>::CAIXS_accessor(aTHX_ SP, cv, stash);

    } else {
        ENTER;
        PUSHMARK(--SP); /* SP -= items */
        call_sv(keys->lazy_cb, G_SCALAR);
        SPAGAIN;
        LEAVE;

        sv_setsv(keys->storage, *SP);
        *SP = keys->storage;
    }

    CvXSUB(cv) = (XSUBADDR_t)&CAIXS_entersub_wrapper<PrivateClass, is_readonly>;
    SvREFCNT_dec_NN(keys->lazy_cb);
    keys->lazy_cb = NULL;

    return;
}};

template <bool is_readonly>
struct FImpl<PrivateClass, is_readonly> {
static void CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<PrivateClass, is_readonly>(aTHX);
    shared_keys* keys = (shared_keys*)CAIXS_find_keys(cv);

    const int type = PrivateClass; /* for CALL_*_CB */

    if (items == 1) {
        CALL_READ_CB(keys->storage);
        return;
    }

    READONLY_CROAK_CHECK;
    CALL_WRITE_CB(keys->storage, 0);
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
    shared_keys* keys = CAIXS_find_keys(cv);

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
            if (UNLIKELY(!hv_store_ent(obj, keys->hash_key, new_value, 0))) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            return;
                    
        } else {
            HE* hent = hv_fetch_ent(obj, keys->hash_key, 0, 0);
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

    HE* hent;
    if (items > 1) {
        READONLY_CROAK_CHECK;

        hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0);
        GV* glob = hent ? (GV*)HeVAL(hent) : NULL;

        if (UNLIKELY(!glob || !isGV(glob) || SvFAKE(glob))) {
            if (!glob) glob = (GV*)newSV(0);

            gv_init_sv(glob, stash, keys->pkg_key, 0);

            if (hent) {
                /* There was just a stub instead of the full glob */
                SvREFCNT_inc_simple_void_NN((SV*)glob);
                SvREFCNT_dec_NN(HeVAL(hent));
                HeVAL(hent) = (SV*)glob;

            } else {
                if (!hv_store_ent(stash, keys->pkg_key, (SV*)glob, 0)) {
                    SvREFCNT_dec_NN(glob);
                    croak("Couldn't add a glob to package");
                }
            }
        }

        SV* new_value = GvSVn(glob);
        CALL_WRITE_CB(new_value, 0);

        return;
    }
    
    #define TRY_FETCH_PKG_VALUE(stash, keys, hent)                      \
    if (stash && (hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0))) {   \
        SV* sv = GvSV(HeVAL(hent));                                     \
        if (sv && SvOK(sv)) {                                           \
            CALL_READ_CB(sv);                                           \
            return;                                                     \
        }                                                               \
    }

    TRY_FETCH_PKG_VALUE(stash, keys, hent);

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
            TRY_FETCH_PKG_VALUE(stash, keys, hent);
        }
    }

    /* XSRETURN_UNDEF */
    CALL_READ_CB(&PL_sv_undef);
    return;
}};

#endif /* __INHERITED_XS_IMPL_H_ */
