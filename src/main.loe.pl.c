#include "config.h"
#include <zlib.h>
#include <stdint.h>
#include <assert.h>
#include <string.h>
#define __USE_LARGEFILE64
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>

#define TOSTR2(x) #x
#define TOSTR(x) TOSTR2(x)

#define elog(f,args...) fprintf(stderr,"ERROR: " PACKAGE_NAME "/" __FILE__ "[" TOSTR(__LINE__) "]:%s->" f "\n",__FUNCTION__,##args)
#define clog(f,args...) fprintf(stderr,"CRITICAL: " PACKAGE_NAME "/" __FILE__ "[" TOSTR(__LINE__) "]:%s->" f "\n",__FUNCTION__,##args)
#define ilog(f,args...) fprintf(stderr,"INFO: " PACKAGE_NAME "/" __FILE__ "[" TOSTR(__LINE__) "]:%s->" f "\n",__FUNCTION__,##args)
#define wlog(f,args...) fprintf(stderr,"WARNING: " PACKAGE_NAME "/" __FILE__ "[" TOSTR(__LINE__) "]:%s->" f "\n",__FUNCTION__,##args)
#define critmalloc(sz,f,args...) clog(f"Can't allocate %zu bytes.",##args,sz)
#define critrealloc(sz,f,args...) clog(f"Can't re-allocate to %zu bytes.",##args,sz)
#define errnolog(f,args...) elog(f"; strerror: %s.",##args,strerror(errno))
#define typemax(t) ((t)((t)-1 < 0 ? ((t)1 << (sizeof (t) * 8 - 2)) - 1 + ((t)1 << (sizeof (t) * 8 - 2)) : -1))

loe::replace({SET_INI_INT64},{int64_t});
loe::replace({SET_INI_UINT64},{uint64_t});
loe::replace({SET_INI_ASSERT},{assert});
loe::replace({SET_INI_BOOLEAN},{int});
loe::replace({SET_INI_FALSE},{0});
loe::replace({SET_INI_TRUE},{1});

set::ini_works;

static SET_INI_BOOLEAN
	opt_show_help=SET_INI_FALSE,opt_show_version=SET_INI_FALSE,
	opt_decompress=SET_INI_FALSE,opt_syntax_error=SET_INI_FALSE;

static int opt_compression_level=Z_BEST_COMPRESSION;

set::gperfing{
	%compare-lengths
	%define hash-function-name cmplevel_hash
	%define lookup-function-name cmplevel_in_word_set
	%enum
	%struct-type
	%readonly-tables
	struct cmplevel_flag{const char*name;int level;}
	%%
	none,Z_NO_COMPRESSION
	default,Z_DEFAULT_COMPRESSION
	speed,Z_BEST_SPEED
}

enum slurpfile_textpath_result{
	slurpfile_textpath_ok,slurpfile_textpath_pathsz_overflow_error,
	slurpfile_textpath_critical_malloc_error,slurpfile_textpath_open_file_error,
	slurpfile_textpath_file_seek_error,slurpfile_textpath_get_file_size_error,
	slurpfile_textpath_file_too_big_error,slurpfile_textpath_file_read_error
};

static enum slurpfile_textpath_result slurpfile_textpath(char **ret,
const char*path,size_t pathsz){
	size_t cpathsz;
	if(__builtin_add_overflow(pathsz,1,&cpathsz)){
		elog("Unexpected overflow.");
		return slurpfile_textpath_pathsz_overflow_error;
	}
	char *m=malloc(cpathsz);
	if(!m){
		critmalloc(cpathsz,"While reading file '%.*s'. ",(int)pathsz,path);
		return slurpfile_textpath_critical_malloc_error;
	}
	memcpy(m,path,pathsz);
	m[pathsz]='\0';
	FILE *f=fopen64(m,"rb");
	if(!f){
		errnolog("Failed to open file '%.*s'",(int)pathsz,path);
		free(m);
		return slurpfile_textpath_open_file_error;
	}
	free(m);
	if(fseeko64(f,0,SEEK_END)==-1){
		errnolog("Failed to change the file pointer in the file '%.*s'",(int)pathsz,path);
		fclose(f);
		return slurpfile_textpath_file_seek_error;
	}
	__off64_t fsz=ftello64(f);
	if(fsz==-1){
		errnolog("Failed to get file size '%.*s'",(int)pathsz,path);
		fclose(f);
		return slurpfile_textpath_get_file_size_error;
	}
	if(fseeko64(f,0,SEEK_SET)==-1){
		errnolog("Failed to change the file pointer in the file '%.*s'",(int)pathsz,path);
		fclose(f);
		return slurpfile_textpath_file_seek_error;
	}
	size_t cfdatasz;
	if(__builtin_add_overflow(fsz,1,&cfdatasz)){
		elog("The file is too large '%.*s'. The maximum file size allowed is %zu bytes.",(int)pathsz,path,typemax(size_t)-1);
		fclose(f);
		return slurpfile_textpath_file_too_big_error;
	}
	m=malloc(cfdatasz);
	if(!m){
		critmalloc(cfdatasz,"While reading file '%.*s'. ",(int)pathsz,path);
		fclose(f);
		return slurpfile_textpath_critical_malloc_error;
	}
	if(fread(m,fsz,1,f)!=1){
		elog("While reading file '%.*s'.",(int)pathsz,path);
		free(m);
		fclose(f);
		return slurpfile_textpath_file_read_error;
	}
	m[fsz]='\0';
	fclose(f);
	*ret=m;
	return slurpfile_textpath_ok;
}

static SET_INI_BOOLEAN opt_report_group(const char*gn,size_t gz,const void*udata){
	elog("Unknown group of options '[%.*s]'.",(int)gz,gn);
	opt_syntax_error=SET_INI_TRUE;
	return SET_INI_TRUE;
}

static const struct opt_group * opt_in_word_set(register const char*,register size_t);

static SET_INI_BOOLEAN opt_report_key(const struct SET_INI_GROUP*g,
const char *gn,size_t gz,const char*kn,size_t kz,const char*v,
size_t vz,SET_INI_INT64 i,enum SET_INI_TYPE t,const void*udata){
	elog("Unknown option '[%.*s] %.*s'.",(int)gz,gn,(int)kz,kn);
	opt_syntax_error=SET_INI_TRUE;
	return SET_INI_TRUE;
}

loe::replace({LOE_STACK_MALLOC},{malloc});
loe::replace({LOE_STACK_REALLOC},{realloc});
loe::replace({LOE_STACK_FREE},{free});
loe::replace({LOE_STACK_LOG_CRITICAL_MALLOC_ERROR},{critmalloc(rsz,"")});
loe::replace({LOE_STACK_LOG_CRITICAL_REALLOC_ERROR},{critrealloc(rsz,"")});
loe::replace({LOE_STACK_LOG_OVERFLOW_ERROR},{clog("Overflow.")});
loe::replace({LOE_STACK_ASSERT},{assert});

loe::stack(tcstr){
	::index_type{size_t};
	::length{size};
	::queue{max_size};
	::array{{char}{data}};
	::allstatic;
	size_t size,max_size;
	char data[];
}

static struct tcstr
	*opt_in_file=NULL,*opt_out_file=NULL;

#define DEFAULT_INPUT_BUFFER_SIZE 0x100000
#define DEFAULT_OUTPUT_BUFFER_SIZE DEFAULT_INPUT_BUFFER_SIZE*2

static size_t
	opt_in_buf_size=DEFAULT_INPUT_BUFFER_SIZE,
	opt_out_buf_size=DEFAULT_OUTPUT_BUFFER_SIZE;

set::ini_info(opt){
	empty{
		names ""
		keys{
			setbool{
				names "--help" "h" "--version" "v" "--decompress" "d"
				decl "SET_INI_BOOLEAN *pb;"
				atts ".setbool={&opt_show_help}" ".setbool={&opt_show_help}"
					".setbool={&opt_show_version}" ".setbool={&opt_show_version}"
					".setbool={&opt_decompress}" ".setbool={&opt_decompress}"
				onload{
					if(t==SET_INI_TYPE_BOOLEAN){
						k->setbool.pb[0]=SET_INI_TRUE;
						return SET_INI_TRUE;
					}
					elog("'%.*s=%.*s' - type mismatch. The parameter does not take values.",(int)kz,kn,(int)vz,v);
					opt_syntax_error=SET_INI_TRUE;
					return SET_INI_TRUE;
				}
			}
			level{
				names "--compression-level" "l"
				decl "int *pcmplevel;"
				atts ".level={&opt_compression_level}" ".level={&opt_compression_level}"
				onload{
					if(t!=SET_INI_TYPE_BOOLEAN){
						if(t==SET_INI_TYPE_STRING){
							const struct cmplevel_flag*f=cmplevel_in_word_set(v,vz);
							if(f){
								k->level.pcmplevel[0]=f->level;
							}else{
								elog("'%.*s=%.*s' - unknown string value. Accepted string values: none,default,speed.",(int)kz,kn,(int)vz,v);
								opt_syntax_error=SET_INI_TRUE;
							}
						}else{
							if(i>=-1 && i<=9){
								k->level.pcmplevel[0]=i;
							}else{
								elog("'%.*s=%.*s' - value is out the range([-1..9]).",(int)kz,kn,(int)vz,v);
								opt_syntax_error=SET_INI_TRUE;
							}
						}
					}else{
						elog("'%.*s' - missing value([-1..9]|none|default|speed).",(int)kz,kn);
						opt_syntax_error=SET_INI_TRUE;
					}
					return SET_INI_TRUE;
				}
			}
			iniconf{
				names "--in-conf" "c"
				onload{
					SET_INI_BOOLEAN e=SET_INI_TRUE;
					if(t!=SET_INI_TYPE_BOOLEAN){
						char *inistr;
						switch(slurpfile_textpath(&inistr,v,vz)){
							case slurpfile_textpath_ok:{
								switch(set_ini_parse_string((SET_INI_GROUP_IN_WORD_SET)opt_in_word_set,
								inistr,opt_report_group,opt_report_key,udata)){
									case SET_INI_PARSER_OK:{
										break;
									}
									case SET_INI_PARSER_UTF8_ERROR:{
										elog("The corrupted UTF-8 encoding of the file '%.*s'.",(int)vz,v);
										opt_syntax_error=SET_INI_TRUE;
										break;
									}
									case SET_INI_PARSER_CANCELLED:{
										e=SET_INI_FALSE;
										break;
									}
								}
								free(inistr);
								break;
							}
							default:{
								opt_syntax_error=SET_INI_TRUE;
								break;
							}
							case slurpfile_textpath_critical_malloc_error:{
								e=SET_INI_FALSE;
								break;
							}
						}
					}else{
						elog("'%.*s' - missing value(path to the configuration file).",(int)kz,kn);
						opt_syntax_error=SET_INI_TRUE;
					}
					return e;
				}
			}
			setstring{
				names "--in-file" "i" "--out-file" "o"
				decl "struct tcstr**pstr;const char*msg;"
				atts ".setstring={&opt_in_file,\"the path to the input file\"}" ".setstring={&opt_in_file,\"the path to the input file\"}"
				".setstring={&opt_out_file,\"the path to the output file\"}" ".setstring={&opt_out_file,\"the path to the output file\"}"
				onload{
					SET_INI_BOOLEAN e=SET_INI_TRUE;
					if(t!=SET_INI_TYPE_BOOLEAN){
						if(!k->setstring.pstr[0]){
							if(tcstr_newout(k->setstring.pstr,vz+1)){
								k->setstring.pstr[0]->size=vz+1;
								k->setstring.pstr[0]->data[vz]='\0';
								memcpy(k->setstring.pstr[0]->data,v,vz);
							}else{
								clog("While trying to allocate memory for a file name(%s) '%.*s'.",k->setstring.msg,(int)vz,v);
								e=SET_INI_FALSE;
							}
						}else{
							wlog("Attempt to redefine %s '%s'.",k->setstring.msg,opt_in_file->data);
							k->setstring.pstr[0]->size=0;
							switch(tcstr_occupy(&k->setstring.pstr[0],vz+1)){
								case tcstr_occupy_ok:
								case tcstr_occupy_ok_new_pointer:{
									k->setstring.pstr[0]->size=vz+1;
									k->setstring.pstr[0]->data[vz]='\0';
									memcpy(k->setstring.pstr[0]->data,v,vz);
									break;
								}
								case tcstr_occupy_overflow_error:{
									elog("While trying to occupy memory for a file name(%s).",k->setstring.msg);
									e=SET_INI_FALSE;
									break;
								}
								case tcstr_occupy_critical_realloc_error:{
									clog("While trying to re-allocate memory for a file name(%s) '%.*s'.",k->setstring.msg,(int)vz,v);
									e=SET_INI_FALSE;
									break;
								}
							}
						}
					}else{
						elog("'%.*s' - missing value(%s).",(int)kz,kn,k->setstring.msg);
						opt_syntax_error=SET_INI_TRUE;
					}
					return e;
				}
			}
			setbufsize{
				names "--in-buffer-size" "ibs" "--out-buffer-size" "obs"
				decl "size_t *psz;"
				atts ".setbufsize={&opt_in_buf_size}" ".setbufsize={&opt_in_buf_size}"
					".setbufsize={&opt_out_buf_size}" ".setbufsize={&opt_out_buf_size}"
				onload{
					if(t==SET_INI_TYPE_SINT64){
						if(i!=0 && ((SET_INI_UINT64)i)<=typemax(size_t)){
							k->setbufsize.psz[0]=i;
						}else{
							elog("'%.*s=%.*s' - value is out of the range([1..%zu]).",
								(int)kz,kn,(int)vz,v,typemax(size_t));
							opt_syntax_error=SET_INI_TRUE;
						}
					}else{
						elog("'%.*s' - type mismatch.",(int)kz,kn);
						opt_syntax_error=SET_INI_TRUE;
					}
					return SET_INI_TRUE;
				}
			}
		}
	}
}

enum darc_compress_result{
	darc_compress_ok,darc_compress_critical_malloc_error,
	darc_compress_deflateinit_version_error,darc_compress_deflateinit_level_error,
	darc_compress_deflateinit_critical_undefined_behavior_error,
	darc_compress_fread_error,darc_compress_fwrite_error,
	darc_compress_deflate_stream_error,
	darc_compress_deflate_critical_undefined_behavior_error,
	darc_compress_deflateend_stream_error,
	darc_compress_deflateend_data_error,
	darc_compress_deflateend_critical_undefined_behavior_error
};

static int darc_compress(FILE*inf,FILE*outf,int level,size_t ibs,size_t obs){
	assert(ibs>0 && obs>0);
	size_t totalsize=0;
	Bytef *ibuf,*obuf;
	int overflow;
	if(overflow=__builtin_add_overflow(ibs,obs,&totalsize)){
		ibuf=malloc(ibs);
		if(!ibuf){
			critmalloc(ibs,"");
			return darc_compress_critical_malloc_error;
		}
		obuf=malloc(obs);
		if(!obuf){
			critmalloc(obs,"");
			free(ibuf);
			return darc_compress_critical_malloc_error;
		}
	}else{
		ibuf=malloc(totalsize);
		if(!ibuf){
			critmalloc(totalsize,"");
			return darc_compress_critical_malloc_error;
		}
		obuf=ibuf+ibs;
	}
	z_stream cmp={.zalloc=Z_NULL,.zfree=Z_NULL,.opaque=Z_NULL};
	switch(deflateInit(&cmp,level)){
		case Z_OK:{
			break;
		}
		case Z_STREAM_ERROR:{
			elog("defaultInit: Invalid compression level(%i).",level);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateinit_level_error;
		}
		case Z_VERSION_ERROR:{
			elog("defaultInit: The zlib vesion is incompatible with the version assumed(%s). msg='%s'.",
				ZLIB_VERSION,cmp.msg==Z_NULL?"":cmp.msg);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateinit_version_error;
		}
		case Z_MEM_ERROR:{
			clog("defaultInit: Not enough memory. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_critical_malloc_error;
		}
		default:{
			clog("defaultInit: Undefined behavior.");
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateinit_critical_undefined_behavior_error;
		}
	}
	cmp.next_out=obuf;
	cmp.avail_out=obs;
	while(1){
		cmp.avail_in=fread(ibuf,1,ibs,inf);
		if(ferror(inf)){
			elog("Input error.");
			deflateEnd(&cmp);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_fread_error;
		}
		if(!cmp.avail_in)
			break;
		cmp.next_in=ibuf;
		do{
l_ok:		switch(deflate(&cmp,Z_NO_FLUSH)){
				case Z_OK:{
					goto l_ok;
				}
				case Z_BUF_ERROR:{
					if(!cmp.avail_out){
						if(fwrite(obuf,1,obs,outf)!=obs){
							elog("Output error.");
							deflateEnd(&cmp);
							if(overflow)
								free(obuf);
							free(ibuf);
							return darc_compress_fwrite_error;
						}
						cmp.next_out=obuf;
						cmp.avail_out=obs;
						continue;
					}
					break;
				}
				case Z_STREAM_ERROR:{
					elog("The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
					deflateEnd(&cmp);
					if(overflow)
						free(obuf);
					free(ibuf);
					return darc_compress_deflate_stream_error;
				}
				default:{
					clog("default(Z_NO_FLUSH): Undefined behavior.");
					deflateEnd(&cmp);
					if(overflow)
						free(obuf);
					free(ibuf);
					return darc_compress_deflate_critical_undefined_behavior_error;
				}
			}
		}while(cmp.avail_in);
	}
	int e;
	while((e=deflate(&cmp,Z_FINISH))!=Z_STREAM_END){
		switch(e){
			case Z_OK:
			case Z_BUF_ERROR:{
				if(fwrite(obuf,1,obs,outf)!=obs){
					elog("Output error.");
					deflateEnd(&cmp);
					if(overflow)
						free(obuf);
					free(ibuf);
					return darc_compress_fwrite_error;
				}
				cmp.avail_out=obs;
				cmp.next_out=obuf;
				continue;
			}
			case Z_STREAM_ERROR:{
				elog("The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
				deflateEnd(&cmp);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_compress_deflate_stream_error;
			}
			default:{
				clog("Undefined behavior.");
				deflateEnd(&cmp);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_compress_deflate_critical_undefined_behavior_error;
			}
		}
	}
	if(obs-cmp.avail_out){
		if(fwrite(obuf,1,obs-cmp.avail_out,outf)!=obs-cmp.avail_out){
			elog("Output error.");
			deflateEnd(&cmp);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_fwrite_error;
		}
	}
	switch(deflateEnd(&cmp)){
		case Z_OK:{
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_ok;
		}
		case Z_STREAM_ERROR:{
			elog("The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateend_stream_error;
		}
		case Z_DATA_ERROR:{
			elog("The stream was freed prematurely. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateend_data_error;
		}
		default:{
			clog("Undefined behavior.");
			if(overflow)
				free(obuf);
			free(ibuf);
			return darc_compress_deflateend_critical_undefined_behavior_error;
		}
	}
}

enum darc_decompress_result{
	darc_decompress_ok,
	darc_decompress_critical_malloc_error,
	darc_decompress_fread_error,
	darc_decompress_inflateinit_version_error,
	darc_decompress_inflateinit_stream_error,
	darc_decompress_inflateinit_critical_memory_error,
	darc_decompress_inflateinit_ciritcal_undefined_behavior_error,
	darc_decompress_fwrite_error,
	darc_decompress_inflateend_stream_error,
	darc_decompress_inflateend_critical_undefined_behavior_error,
	darc_decompress_inflate_need_dict_error,
	darc_decompress_inflate_data_error,
	darc_decompress_inflate_stream_error,
	darc_decompress_inflate_critical_memory_error,
	darc_decompress_no_data_error
};

static int darc_decompress(FILE*inf,FILE*outf,size_t ibs,size_t obs){
	Bytef *ibuf,*obuf;
	size_t totalsize;
	int overflow;
	if(overflow=__builtin_add_overflow(ibs,obs,&totalsize)){
		ibuf=malloc(ibs);
		if(!ibuf){
			critmalloc(ibs,"");
			return darc_decompress_critical_malloc_error;
		}
		obuf=malloc(obs);
		if(!obuf){
			critmalloc(obs,"");
			free(ibuf);
			return darc_decompress_critical_malloc_error;
		}
	}else{
		ibuf=malloc(totalsize);
		if(!ibuf){
			critmalloc(totalsize,"");
			return darc_decompress_critical_malloc_error;
		}
		obuf=ibuf+ibs;
	}
	z_stream cmp={.zalloc=Z_NULL,.zfree=Z_NULL,.next_in=ibuf,.opaque=Z_NULL};
	cmp.avail_in=fread(ibuf,1,ibs,inf);
	if(ferror(inf)){
		elog("Input error.");
		inflateEnd(&cmp);
		if(overflow)
			free(obuf);
		free(ibuf);
		return darc_decompress_fread_error;
	}
	if(cmp.avail_in){
		cmp.avail_out=obs;
		cmp.next_out=obuf;
		switch(inflateInit(&cmp)){
			case Z_OK:{
				break;
			}
			case Z_VERSION_ERROR:{
				elog("inflateInit: The zlib vesion is incompatible with the version assumed(%s). msg='%s'.",
					ZLIB_VERSION,cmp.msg==Z_NULL?"":cmp.msg);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_decompress_inflateinit_version_error;
			}
			case Z_STREAM_ERROR:{
				elog("inflateInit: The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_decompress_inflateinit_stream_error;
			}
			case Z_MEM_ERROR:{
				clog("inflateInit: Not enough memory. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_decompress_inflateinit_critical_memory_error;
			}
			default:{
				clog("inflateInit: Undefined behavior.");
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_decompress_inflateinit_ciritcal_undefined_behavior_error;
			}
		}
		do{
			do{
l_ok:			switch(inflate(&cmp,Z_NO_FLUSH)){
					case Z_OK:{
						goto l_ok;
					}
					case Z_STREAM_END:{
						if(obs-cmp.avail_out){
							if(fwrite(obuf,1,obs-cmp.avail_out,outf)!=obs-cmp.avail_out){
								elog("Output error.");
								inflateEnd(&cmp);
								if(overflow)
									free(obuf);
								free(ibuf);
								return darc_decompress_fwrite_error;
							}
						}
						switch(inflateEnd(&cmp)){
							case Z_OK:{
								if(overflow)
									free(obuf);
								free(ibuf);
								return darc_decompress_ok;
							}
							case Z_STREAM_ERROR:{
								elog("inflateEnd: The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
								if(overflow)
									free(obuf);
								free(ibuf);
								return darc_decompress_inflateend_stream_error;
							}
							default:{
								clog("inflateEnd: Undefined behavior.");
								if(overflow)
									free(obuf);
								free(ibuf);
								return darc_decompress_inflateend_critical_undefined_behavior_error;
							}
						}
					}
					case Z_BUF_ERROR:{
						if(!cmp.avail_out){
							if(fwrite(obuf,1,obs,outf)!=obs){
								elog("Output error.");
								inflateEnd(&cmp);
								if(overflow)
									free(obuf);
								free(ibuf);
								return darc_decompress_fwrite_error;
							}
							cmp.avail_out=obs;
							cmp.next_out=obuf;
						}
						break;
					}
					case Z_NEED_DICT:{
						elog("inflate: A preset dictionary required at this point. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
						inflateEnd(&cmp);
						if(overflow)
							free(obuf);
						free(ibuf);
						return darc_decompress_inflate_need_dict_error;
					}
					case Z_DATA_ERROR:{
						elog("inflate: The input data was corrupted. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
						inflateEnd(&cmp);
						if(overflow)
							free(obuf);
						free(ibuf);
						return darc_decompress_inflate_data_error;
					}
					case Z_STREAM_ERROR:{
						elog("inflate: The stream state was inconsistent. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
						inflateEnd(&cmp);
						if(overflow)
							free(obuf);
						free(ibuf);
						return darc_decompress_inflate_stream_error;
					}
					case Z_MEM_ERROR:{
						clog("inflate: Not enough memory. msg='%s'.",cmp.msg==Z_NULL?"":cmp.msg);
						inflateEnd(&cmp);
						if(overflow)
							free(obuf);
						free(ibuf);
						return darc_decompress_inflate_critical_memory_error;
					}
				}
			}while(cmp.avail_in);
			cmp.avail_in=fread(ibuf,1,ibs,inf);
			if(ferror(inf)){
				elog("Input error.");
				inflateEnd(&cmp);
				if(overflow)
					free(obuf);
				free(ibuf);
				return darc_decompress_fread_error;
			}
			if(!cmp.avail_in)
				break;
			cmp.next_in=ibuf;
		}while(1);
	}
	return darc_decompress_no_data_error;
}

int main(int i,char**v){
	int exit_code=1;
	FILE *readfrom=stdin;
	FILE *writeto=stdout;
	if(i>1){
		switch(set_ini_parse_cmd((SET_INI_GROUP_IN_WORD_SET)opt_in_word_set,
			i-1,(const char*const*)v+1,opt_report_group,opt_report_key,NULL)){
			case SET_INI_PARSER_OK:{
				if(opt_syntax_error==SET_INI_FALSE){
					if(opt_show_help==SET_INI_TRUE || opt_show_version==SET_INI_TRUE){
						if(opt_show_help){
							ilog("\n+-------------------+------------+------------------+------------+\n|   long options    |   short    |    vaue type     |description |\n|                   |  options   |                  |            |\n+-------------------+------------+------------------+------------+\n|      --help       |     h      |     boolean      | show this  |\n|                   |            |                  |    help    |\n+-------------------+------------+------------------+------------+\n|     --version     |     v      |     boolean      |show version|\n+-------------------+------------+------------------+------------+\n|   --decompress    |     d      |     boolean      | decompress |\n|                   |            |                  | input data |\n+-------------------+------------+------------------+------------+\n|                   |            |     [-1..9]|     |compression |\n|--compression-level|     l      |none|default|speed|   level    |\n|                   |            |                  |            |\n+-------------------+------------+------------------+------------+\n|                   |            |                  |input buffer|\n| --in-buffer-size  |    ibs     |      size_t      |    size    |\n|                   |            |                  |            |\n+-------------------+------------+------------------+------------+\n| --out-buffer-size |    obs     |      size_t      |   output   |\n|                   |            |                  |buffer size |\n+-------------------+------------+------------------+------------+\n|     --in-file     |     i      |      string      | read data  |\n|                   |            |                  |from a file |\n+-------------------+------------+------------------+------------+\n|    --out-file     |     o      |      string      | write data |\n|                   |            |                  | to a file  |\n+-------------------+------------+------------------+------------+\n|                   |            |                  |  to load   |\n|     --in-conf     |     c      |      string      |  settings  |\n|                   |            |                  |from a file |\n+-------------------+------------+------------------+------------+\nsize_t:[1..%zu]\n",typemax(size_t));
						}
						if(opt_show_version){
							ilog(PACKAGE_VERSION);
						}
					}else{
						if(opt_in_file){
							readfrom=fopen64(opt_in_file->data,"rb");
							if(!readfrom){
								errnolog("Can't open file '%s'",opt_in_file->data);
								tcstr_free(opt_in_file);
								if(opt_out_file)
									tcstr_free(opt_out_file);
								return exit_code;
							}
						}
						if(opt_out_file){
							writeto=fopen64(opt_out_file->data,"wb");
							if(!writeto){
								errnolog("Can't open file '%s'",opt_out_file->data);
								tcstr_free(opt_out_file);
								if(opt_in_file){
									fclose(readfrom);
									tcstr_free(opt_in_file);
								}
								return exit_code;
							}
						}
						if(opt_decompress){
							exit_code=darc_decompress(readfrom,writeto,
								opt_in_buf_size,opt_out_buf_size)!=darc_decompress_ok;
						}else{
							exit_code=darc_compress(readfrom,writeto,
								opt_compression_level,opt_in_buf_size,opt_out_buf_size)!=darc_compress_ok;
						}
						if(opt_out_file){
							fflush(writeto);
							fclose(writeto);
						}
						if(opt_in_file)
							fclose(readfrom);
					}
				}
				break;
			}
			case SET_INI_PARSER_CANCELLED:{
				break;
			}
			case SET_INI_PARSER_UTF8_ERROR:{
				elog("A command-line encoding(UTF-8) error was detected.");
				break;
			}
		}
		if(opt_out_file)
			tcstr_free(opt_out_file);
		if(opt_in_file)
			tcstr_free(opt_in_file);
	}else{
		if(opt_decompress){
			exit_code=darc_decompress(readfrom,writeto,
				opt_in_buf_size,opt_out_buf_size)!=darc_decompress_ok;
		}else{
			exit_code=darc_compress(readfrom,writeto,
				opt_compression_level,opt_in_buf_size,opt_out_buf_size)!=darc_compress_ok;
		}
		fflush(writeto);
	}
	return exit_code;
}
