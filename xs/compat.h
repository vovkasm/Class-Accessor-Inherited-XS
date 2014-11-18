#ifndef __INHERITED_XS_COMPAT_H_
#define __INHERITED_XS_COMPAT_H_

#ifndef SvREFCNT_dec_NN
#define SvREFCNT_dec_NN SvREFCNT_dec
#endif

#ifdef dNOOP
#undef dNOOP
#define dNOOP
#endif

#ifndef gv_init_pvn
#define gv_init_pvn(gv, stash, name, len, flags) gv_init(gv, stash, name, len, 0)
#endif

#endif
