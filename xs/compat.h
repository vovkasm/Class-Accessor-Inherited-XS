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

#endif
