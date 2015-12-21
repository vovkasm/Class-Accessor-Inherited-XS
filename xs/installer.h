#ifndef __INHERITED_XS_INSTALLER_H_
#define __INHERITED_XS_INSTALLER_H_

inline void
CAIXS_payload_attach(pTHX_ CV* cv, AV* keys_av) {
#ifndef MULTIPLICITY
    CvXSUBANY(cv).any_ptr = (void*)AvARRAY(keys_av);
#endif

    sv_magicext((SV*)cv, (SV*)keys_av, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)keys_av);
    SvRMAGICAL_off((SV*)cv);
}

template <AccessorTypes type> static
shared_keys*
CAIXS_payload_init(pTHX_ CV* cv) {
    AV* keys_av = newAV();

    av_extend(keys_av, ALLOC_SIZE[type]);
    AvFILLp(keys_av) = ALLOC_SIZE[type];

    CAIXS_payload_attach(aTHX_ cv, keys_av);
    return (shared_keys*)AvARRAY(keys_av);
}

template <AccessorTypes type> static
CV*
CAIXS_install_cv(pTHX_ SV* full_name) {
    STRLEN len;

    const char* full_name_buf = SvPV_const(full_name, len);
#ifdef CAIX_BINARY_UNSAFE
    if (strnlen(full_name_buf, len) < len) {
        croak("Attempted to install binary accessor, but they're not supported on this perl");
    }
#endif

    CV* cv = Perl_newXS_len_flags(aTHX_ full_name_buf, len, &CAIXS_entersub_wrapper<type>, __FILE__, NULL, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    return cv;
}

template <AccessorTypes type> static
shared_keys*
CAIXS_install_accessor(pTHX_ SV* full_name) {
    CV* cv = CAIXS_install_cv<type>(aTHX_ full_name);
    return CAIXS_payload_init<type>(aTHX_ cv);
}

#endif /* __INHERITED_XS_INSTALLER_H_ */
