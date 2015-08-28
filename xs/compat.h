#ifndef __INHERITED_XS_COMPAT_H_
#define __INHERITED_XS_COMPAT_H_

#if (PERL_VERSION < 21)
#undef mg_findext
#define NEED_mg_findext
#endif

#ifndef SvREFCNT_dec_NN
#define SvREFCNT_dec_NN SvREFCNT_dec
#endif

#ifdef dNOOP
#undef dNOOP
#define dNOOP
#endif

#ifndef gv_init_sv
#define gv_init_sv(gv, stash, sv, flags) gv_init(gv, stash, SvPVX(sv), SvLEN(sv), flags | SvUTF8(sv))
#endif

#if (PERL_VERSION < 16)
#define Perl_newXS_len_flags(name, len, subaddr, filename, proto, const_svp, flags) Perl_newXS_flags(name, subaddr, filename, proto, flags)
#endif

#endif /* __INHERITED_XS_COMPAT_H_ */
