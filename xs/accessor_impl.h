#ifndef __INHERITED_XS_IMPL_H_
#define __INHERITED_XS_IMPL_H_

/*
    av_extend() always gives us at least 4 elements, so don't bother with
    saving memory for need_cb = false version until this struct grows larger
*/

struct shared_keys {
    union {
        SV* hash_key;
        SV* storage;
    };
    SV* pkg_key;
    SV* read_cb;
    SV* write_cb;
};

enum AccessorTypes {
    Inherited,
    InheritedCb,
    PrivateClass
};

/*
    These macroses rely heavily on SP not being touched inside the
    CAIXS_inherited_accessor function body expect for the start shift to the top of the stack.

    They also expect nothing but XSRETURN(1) after them (or, at least, nothing touching stack,
    as in the 1st CALL_WRITE_CB() call). They're left as two statements for the reader's sanity.

    call_sv() is stripped off the most of a normal call sequence.
*/

#define CALL_READ_CB(result, cb)        \
    if ((type == InheritedCb) && cb) {  \
        ENTER;                          \
        PUSHMARK(SP);                   \
        *(SP+1) = result;               \
        call_sv(cb, G_SCALAR);          \
        LEAVE;                          \
    } else {                            \
        *(SP+1) = result;               \
    }                                   \

#define CALL_WRITE_CB(slot, cb, need_alloc) \
    if ((type == InheritedCb) && cb) {      \
        ENTER;                              \
        PUSHMARK(SP);                       \
        call_sv(cb, G_SCALAR);              \
        SPAGAIN;                            \
        LEAVE;                              \
        if (need_alloc) slot = newSV(0);    \
        sv_setsv(slot, *SP);                \
        *SP = slot;                         \
    } else {                                \
        if (need_alloc) slot = newSV(0);    \
        sv_setsv(slot, *(SP+2));            \
        *(SP+1) = slot;                     \
    }                                       \

template <AccessorTypes type> static
XSPROTO(CAIXS_accessor);

template <AccessorTypes type> static
OP *
CAIXS_entersub(pTHX) {
    dSP;

    /* some older gcc's can't deduce correct function - have to add explicit cast  */
    typedef void (*XSPROTO_CB)(pTHX_ CV*);

    CV* sv = (CV*)TOPs;
    if (sv && (SvTYPE(sv) == SVt_PVCV) && (CvXSUB(sv) == (XSPROTO_CB)&CAIXS_accessor<type>)) {
        /*
            Assert against future XPVCV layout change - as for now, xcv_xsub shares space with xcv_root
            which are both pointers, so address check is enough, and there's no need to look into op_flags for CvISXSUB.
        */
        assert(CvISXSUB(sv));

        POPs; PUTBACK;
        CAIXS_accessor<type>(aTHX_ sv);

        return NORMAL;

    } else {
        PL_op->op_ppaddr = PL_ppaddr[OP_ENTERSUB];
        return PL_ppaddr[OP_ENTERSUB](aTHX);
    }
}

template <AccessorTypes type> inline
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
        op->op_ppaddr = &CAIXS_entersub<type>;
    }
}

inline shared_keys*
CAIXS_find_keys(CV* cv) {
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

    return keys;
}

template <>
XSPROTO(CAIXS_accessor<PrivateClass>) {
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<PrivateClass>(aTHX);
    shared_keys* keys = (shared_keys*)CAIXS_find_keys(cv);

    if (items > 1) {
        sv_setsv(keys->storage, *(SP+2));
    }

    *(SP+1) = keys->storage;
    XSRETURN(1);
}

template <AccessorTypes type> static
XSPROTO(CAIXS_accessor) {
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<type>(aTHX);
    shared_keys* keys = CAIXS_find_keys(cv);

    SV* self = *(SP+1);
    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV) {
            croak("Inherited accessors can only work with object instances that is hash-based");
        }

        if (items > 1) {
            SV* new_value;
            CALL_WRITE_CB(new_value, keys->write_cb, 1);
            if (!hv_store_ent(obj, keys->hash_key, new_value, 0)) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            XSRETURN(1);
                    
        } else {
            HE* hent = hv_fetch_ent(obj, keys->hash_key, 0, 0);
            if (hent) {
                CALL_READ_CB(HeVAL(hent), keys->read_cb);
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
                SvREFCNT_inc_simple_void_NN((SV*)glob);
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
        CALL_WRITE_CB(new_value, keys->write_cb, 0);

        XSRETURN(1);
    }
    
    #define TRY_FETCH_PKG_VALUE(stash, keys, hent)                      \
    if (stash && (hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0))) {   \
        SV* sv = GvSV(HeVAL(hent));                                     \
        if (sv && SvOK(sv)) {                                           \
            CALL_READ_CB(sv, keys->read_cb);                            \
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

    /* XSRETURN_UNDEF */
    CALL_READ_CB(&PL_sv_undef, keys->read_cb);
    XSRETURN(1);
}

#endif /* __INHERITED_XS_IMPL_H_ */
