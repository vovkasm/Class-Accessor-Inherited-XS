#ifndef __INHERITED_XS_INSTALLER_H_
#define __INHERITED_XS_INSTALLER_H_

inline shared_keys*
CAIXS_payload_attach(pTHX_ CV* cv) {
    GV* gv = CvGV(cv);
    HV* stash = GvSTASH(gv);
    MAGIC* mg = mg_findext((SV*)stash, PERL_MAGIC_ext, &sv_payload_marker);

    if (!mg) {
        AV* meta = newAV();
        bool was_rmg = SvRMAGICAL((SV*)stash);
        mg = sv_magicext((SV*)stash, (SV*)meta, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
        if (!was_rmg) SvRMAGICAL_off((SV*)stash);
        SvREFCNT_dec_NN((SV*)meta);
    }

    AV* meta = (AV*)(mg->mg_obj);
    int free_idx = AvFILLp(meta) + 1;
    av_extend(meta, AvFILLp(meta) + 4);
    AvFILLp(meta) += 4;

    CvXSUBANY(cv).any_i32 = free_idx;

    sv_magicext((SV*)cv, (SV*)meta, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvRMAGICAL_off((SV*)cv);

    return (shared_keys*)(AvARRAY(meta) + free_idx);
}

template <AccessorType type> static
shared_keys*
CAIXS_payload_init(pTHX_ CV* cv) {
    return CAIXS_payload_attach(aTHX_ cv);
}

template <AccessorType type, AccessorOpts opts> static
CV*
CAIXS_install_cv(pTHX_ SV* full_name) {
    STRLEN len;

    const char* full_name_buf = SvPV_const(full_name, len);
#ifdef CAIX_BINARY_UNSAFE
    if (strnlen(full_name_buf, len) < len) {
        croak("Attempted to install binary accessor, but they're not supported on this perl");
    }
#endif

    CV* cv = Perl_newXS_len_flags(aTHX_ full_name_buf, len, (&CAIXS_entersub_wrapper<type, opts>), __FILE__, NULL, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    return cv;
}

template <AccessorType type, AccessorOpts opts>
struct CImpl {
static shared_keys* CAIXS_install_accessor(pTHX_ AccessorOpts val, SV* full_name) {
    if (type != InheritedCb && (opts & PushName)) goto next;
    if (type == InheritedCb && (opts & IsReadonly)) goto next;
    if (type == Constructor) goto next;

    if ((val & opts) == opts) {
        CV* cv = CAIXS_install_cv<type, opts>(aTHX_ full_name);
        return CAIXS_payload_init<type>(aTHX_ cv);
    }

next:
    return CImpl<type, (AccessorOpts)(opts-1)>::CAIXS_install_accessor(aTHX_ val, full_name);
}};

template <AccessorType type>
struct CImpl<type, (AccessorOpts)0> {
static shared_keys* CAIXS_install_accessor(pTHX_ int val, SV* full_name) {
    CV* cv = CAIXS_install_cv<type, None>(aTHX_ full_name);
    return CAIXS_payload_init<type>(aTHX_ cv);
}};

#endif /* __INHERITED_XS_INSTALLER_H_ */
