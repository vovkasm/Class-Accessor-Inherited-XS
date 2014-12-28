#ifndef __INHERITED_XS_COMPAT_H_
#define __INHERITED_XS_COMPAT_H_

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

#if defined(_WIN32) || defined(WIN32) || (PERL_VERSION < 18)
#define av_extend_guts(hv, idx, max, alloc, array) av_extend(hv, idx)
#else
#define av_extend_guts(hv, idx, max, alloc, array) Perl_av_extend_guts(aTHX_ hv, idx, max, alloc, array)
#endif

#endif
