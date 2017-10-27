AC_PREREQ([2.69])
AC_CONFIG_AUX_DIR([build-aux])
AC_INIT([darc], [1.0])
AC_CONFIG_SRCDIR([src/loe.pl])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([-Wall -Werror foreign no-dist-gzip dist-xz])

AC_ARG_ENABLE([shadow],
[  --enable-shadow  Turn on the shadow mode],
[case "${enableval}" in
	yes) shadow=true ;;
	no) shadow=false ;;
	*) AC_MSG_ERROR([bad value ${enableval} for --enable-shadow]) ;;
esac],[shadow=false])
AM_CONDITIONAL([SHADOW], [test x$shadow = xtrue])

# Checks for programs.
AC_PROG_CC
PKG_PROG_PKG_CONFIG([0.29.2])

AC_CHECK_PROG([GPERF],[gperf],[yes])
AC_CHECK_PROG([INDENT],[indent],[yes])
AC_CHECK_PROG([DARC],[darc],[yes])
test "$GPERF" != "yes" || test "$INDENT" != "yes" || test "$DARC" != "yes" && AC_MSG_ERROR([Some programs are missing])
# Checks for libraries.
PKG_CHECK_MODULES([ZLIB], [zlib >= 1.2.11])
AC_CHECK_LIB([z], [deflate])

# Checks for header files.

# Checks for typedefs, structures, and compiler characteristics.
AC_C_INLINE
AC_TYPE_INT64_T
AC_TYPE_SIZE_T
AC_TYPE_UINT64_T

# Checks for library functions.
AC_FUNC_MALLOC
AC_FUNC_REALLOC

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
