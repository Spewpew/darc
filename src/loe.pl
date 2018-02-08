#!/usr/bin/perl -w

use POSIX ":sys_wait_h";

my $current_script_path=$0;
my $current_script_dir=$current_script_path=~s/[^\/]*$//r;
my $current_script_base=$current_script_path=~s/^$current_script_dir//r;
my $REGEXP_NESTED_BRACKETS=qr/\{((?:\{(?-1)\}|[^{}])*)\}/;
my $REGEXP_NESTED_PARENTHESES=qr/\(((?:\((?-1)\)|[^()])*)\)/;
my $REGEXP_NESTED_SHARPS=qr/#((?:#(?-1)#|[^#])*)#/;
my $REGEXP_C_ID=qr/(?:[_a-zA-Z\$][a-zA-Z0-9_\$]*)/;

my $REGEXP_C_TYPE=qr/(?:(?:$REGEXP_C_ID\s*){1,}(?:$REGEXP_NESTED_BRACKETS|$REGEXP_NESTED_PARENTHESES)?)/;

sub slurpfile($){
	my $fn=shift;
	open my $fh,'<',$fn or die "$fn >> $!";
	my $rd=join('',<$fh>);
	close $fh or die;
	return $rd;
}

sub overfile($$){
	open my $fh,'>',shift() or die;
	print $fh shift();
	close $fh or die;
}

sub overexe($$){
	open my $fh,'>',shift() or die;
	chmod(((stat $fh)[2] & 07777)|0700,$fh);
	print $fh shift();
	close $fh or die;
}

sub exomod($$){
	my ($p,$d)=(@_);
	my $ch=open(my $fh,'-|') // die;
	if($ch==0){
		my $nh=open(STDIN,'-|') // die;
		if($nh==0){
			print $d;
			exit;
		}
		exec $p or die;
	}
	my $rd=join('',<$fh>);
	close($fh) or die;
	return $rd;
}

sub _gperfing($){
	my $body=shift=~s/^\s*//mrg=~s/\s*$//r;
	return exomod('gperf',$body);
}

sub gperfing($){
	return shift=~s/(^|\W)set::gperfing\s*$REGEXP_NESTED_BRACKETS/$1._gperfing($2)/erg;
}

sub iniinfo($){
	sub _getplain($){
		return shift=~s/($REGEXP_C_ID)\s*$REGEXP_NESTED_BRACKETS//rg;
	}
	sub _getqqs($$){
		my ($plain,$id)=(@_);
		my $qqs=($plain=~/$id((?:\s*"(?:\\"|[^"])*"){1,})/g)[0];
		if(defined $qqs){
			return map(s/\\"/"/rg,$qqs=~/"((?:\\"|[^"])*)"/g);
		}
		return;
	}
	sub _getqq($$){
		my ($plain,$id)=(@_);
		return ($plain=~/$id\s*"((?:\\"|[^"])*)"/)[0];
	}
	sub _getsub($$){
		my ($body,$id)=(@_);
		return ($body=~/$id\s*$REGEXP_NESTED_BRACKETS/)[0];
	}
	sub _iniinfo($$){
		my ($prefix,$body)=(@_);
		my %ini=();
		while($body=~/($REGEXP_C_ID)\s*$REGEXP_NESTED_BRACKETS/g){
			my ($g_prefix,$g_body)=($1,$2);
			my $g_body_plain=_getplain($g_body);
			my @g_names=_getqqs($g_body_plain,'names');
			die if not @g_names;
			my $g_decl=_getqq($g_body_plain,'decl');
			my $g_declfrom=_getqq($g_body_plain,'declfrom');
			my @g_atts=_getqqs($g_body_plain,'atts');
			die if (defined $g_decl or defined $g_declfrom) and not @g_atts;
			my $keys_body=_getsub($g_body,'keys');
			my $keysfrom=_getqq($g_body_plain,'keysfrom');
			if(defined $keysfrom){
				die if not defined $ini{groups}->{$keysfrom};
			}else{
				die if not defined $keys_body;
			}
			if(defined $keys_body){
				while($keys_body=~/($REGEXP_C_ID)\s*$REGEXP_NESTED_BRACKETS/g){
					my ($k_prefix,$k_body)=($1,$2);
					my $k_body_plain=_getplain($k_body);
					my @k_names=_getqqs($k_body_plain,'names');
					die if not @k_names;
					my $k_decl=_getqq($k_body_plain,'decl');
					my @k_declfrom=(_getqqs($k_body_plain,'declfrom'))[0..1];
					my @k_atts=_getqqs($k_body_plain,'atts');
					die if (defined $k_decl or @k_declfrom) and not @k_atts;
					my $k_onload=_getsub($k_body,'onload');
					my @k_onloadfrom=(_getqqs($k_body_plain,'onloadfrom'))[0..1];
					die if (not defined $k_onload and not @k_onloadfrom) or (defined $k_onload and @k_onloadfrom);
					$ini{groups}->{$g_prefix}->{keys}->{$k_prefix}={
						names=>[@k_names],
						decl=>$k_decl,
						declfrom=>[@k_declfrom],
						atts=>[@k_atts],
						onload=>$k_onload,
						onloadfrom=>[@k_onloadfrom]
					};
				}
			}
			$ini{groups}->{$g_prefix}->{names}=[@g_names];
			$ini{groups}->{$g_prefix}->{decl}=$g_decl;
			$ini{groups}->{$g_prefix}->{declfrom}=$g_declfrom;
			$ini{groups}->{$g_prefix}->{atts}=[@g_atts];
			$ini{groups}->{$g_prefix}->{keysfrom}=$keysfrom;
			push @{$ini{orderedgroups}},$g_prefix;
		}
		#~ for my $g (keys %{$ini{groups}}){
			#~ print "Group: $g, names: @{$ini{groups}->{$g}->{names}}, decl: $ini{groups}->{$g}->{decl}, declfrom: $ini{groups}->{$g}->{declfrom}, atts: @{$ini{groups}->{$g}->{atts}}, keysfrom: $ini{groups}->{$g}->{keysfrom}\n";
			#~ for my $k (keys %{$ini{groups}->{$g}->{keys}}){
				#~ print "Key: $k, names: @{$ini{groups}->{$g}->{keys}->{$k}->{names}}, decl: $ini{groups}->{$g}->{keys}->{$k}->{decl}, declfrom: @{$ini{groups}->{$g}->{keys}->{$k}->{declfrom}},atts: @{$ini{groups}->{$g}->{keys}->{$k}->{atts}},onload: $ini{groups}->{$g}->{keys}->{$k}->{onload},onloadfrom: @{$ini{groups}->{$g}->{keys}->{$k}->{onloadfrom}}\n";
			#~ }
		#~ }
		my $groups_struct="struct $prefix\_group{const char *name;const struct SET_INI_KEY*(*in_word_set)(register const char *,register size_t);union{";
		my $groups_for_gperfing='';
		my $group_with_empty_name;
		my $group_with_empty_name_att;
		my $total_onloads='';
		my $total_keys_struct='';
		my $total_keys_gperfed='';
		for my $g (keys %{$ini{groups}}){
			if(not defined $ini{groups}->{$g}->{keysfrom}){
				my $keys_struct="struct $prefix\_$g\_key{const char *name;SET_INI_BOOLEAN (*onload)(const struct $prefix\_group*,const struct $prefix\_$g\_key*,const char *kn,size_t kz,const char *v,size_t vz,SET_INI_INT64 i,enum SET_INI_TYPE t,const void*udata);union{";
				my $keys_for_gperfing='';
				my $key_with_empty_name;
				my $key_with_empty_name_att;
				my $keys_onloads='';
				for my $k (keys %{$ini{groups}->{$g}->{keys}}){
					if(defined $ini{groups}->{$g}->{keys}->{$k}->{decl}){
						$keys_struct.="struct{$ini{groups}->{$g}->{keys}->{$k}->{decl}}$k;";
					}
					if(defined $ini{groups}->{$g}->{keys}->{$k}->{onload}){
						$keys_onloads.="static SET_INI_BOOLEAN $prefix\_$g\_$k\_onload(const struct $prefix\_group*g,const struct $prefix\_$g\_key*k,const char *kn,size_t kz,const char *v,size_t vz,SET_INI_INT64 i,enum SET_INI_TYPE t,const void*udata){$ini{groups}->{$g}->{keys}->{$k}->{onload}}\n";
					}
					for my $nid (0..$#{$ini{groups}->{$g}->{keys}->{$k}->{names}}){
						my $n=${$ini{groups}->{$g}->{keys}->{$k}->{names}}[$nid];
						my $a=${$ini{groups}->{$g}->{keys}->{$k}->{atts}}[$nid];
						if($n ne ''){
							my $onload;
							if(@{$ini{groups}->{$g}->{keys}->{$k}->{onloadfrom}}){
								$onload=",(SET_INI_BOOLEAN(*)(const struct $prefix\_group *,const struct $prefix\_$g\_key *, const char *,size_t,const char *, size_t,SET_INI_INT64, enum SET_INI_TYPE,const void*))$prefix\_${$ini{groups}->{$g}->{keys}->{$k}->{onloadfrom}}[0]_${$ini{groups}->{$g}->{keys}->{$k}->{onloadfrom}}[1]\_onload";
							}else{
								$onload=",$prefix\_$g\_$k\_onload";
							}
							$keys_for_gperfing.="\"$n\"$onload";
							if(defined $a){
								$keys_for_gperfing.=",$a";
							}
							$keys_for_gperfing.="\n";
						}else{
							die if defined $key_with_empty_name;
							$key_with_empty_name=$k;
							$key_with_empty_name_att=$a;
						}
					}
				}
				$total_onloads.=$keys_onloads;
				$keys_struct.="};} __attribute__((packed));";
				$total_keys_struct.="$keys_struct\n";
				$keys_for_gperfing=~s/\s*$//;
				my $keys_gperfed;
				if($keys_for_gperfing ne ''){
					$keys_gperfed=_gperfing(qq{%define lookup-function-name $prefix\_$g\_in_word_set
%define hash-function-name $prefix\_$g\_hash
%struct-type
%omit-struct-type
%compare-lengths
%enum
%readonly-tables
$keys_struct
%%
$keys_for_gperfing
});
					if(defined $key_with_empty_name){
						my $atts='';
						if(defined $key_with_empty_name_att){
							$atts=",$key_with_empty_name_att";
						}
						$keys_gperfed=$keys_gperfed=~s/if \(len <= MAX_WORD_LENGTH/static const struct $prefix\_$g\_key _empty=\{\"\",$prefix\_$g\_$key_with_empty_name\_onload$atts\};\nif(!len)return &_empty;\nif (len <= MAX_WORD_LENGTH/r;
					}
				}elsif(defined $key_with_empty_name){
					my $atts='';
					if(defined $key_with_empty_name_att){
						$atts=",$key_with_empty_name_att";
					}
					$keys_gperfed="static const struct $prefix\_$g\_key *$prefix\_$g\_in_word_set (register const char *str, register size_t len){static const struct $prefix\_$g\_key _empty=\{\"\",$prefix\_$g\_$key_with_empty_name\_onload$atts\};\nreturn len?0:&_empty;}";
				}else{
					die "Group $g\n";
				}
				$total_keys_gperfed.="$keys_gperfed\n";
			}
			if(defined $ini{groups}->{$g}->{decl}){
				$groups_struct.="struct{$ini{groups}->{$g}->{decl}}$g;";
			}
			for my $nid (0..$#{$ini{groups}->{$g}->{names}}){
				my $n=${$ini{groups}->{$g}->{names}}[$nid];
				my $a=${$ini{groups}->{$g}->{atts}}[$nid];
				if($n ne ''){
					$groups_for_gperfing.="\"$n\"";
					if(defined $ini{groups}->{$g}->{keysfrom}){
						#~ $groups_for_gperfing.=",$prefix\_$ini{groups}->{$g}->{keysfrom}_in_word_set";
						$groups_for_gperfing.=",(const struct SET_INI_KEY *(*)(const char *, size_t))$prefix\_$ini{groups}->{$g}->{keysfrom}_in_word_set";
					}else{
						#~ $groups_for_gperfing.=",$prefix\_$g\_in_word_set";
						$groups_for_gperfing.=",(const struct SET_INI_KEY *(*)(const char *, size_t))$prefix\_$g\_in_word_set";
					}
					if(defined $a){
						$groups_for_gperfing.=",$a";
					}
					$groups_for_gperfing.="\n";
				}else{
					die if defined $group_with_empty_name;
					$group_with_empty_name=$g;
					$group_with_empty_name_att=$a;
				}
			}
		}
		$groups_struct.="};} __attribute__((packed));";
		$groups_for_gperfing=$groups_for_gperfing=~s/\s*$//r;
		
		my $groups_gperfed;
		if($groups_for_gperfing ne ''){
			$groups_gperfed=_gperfing(qq{%enum
%define lookup-function-name $prefix\_in_word_set
%define hash-function-name $prefix\_hash
%struct-type
%omit-struct-type
%compare-lengths
%readonly-tables
$groups_struct
%%
$groups_for_gperfing});
			if(defined $group_with_empty_name){
				my $atts='';
				if(defined $group_with_empty_name_att){
					$atts=",$group_with_empty_name_att";
				}
				$groups_gperfed=$groups_gperfed=~s/if \(len <= MAX_WORD_LENGTH/static const struct $prefix\_group _empty=\{"",(const struct SET_INI_KEY *(*)(const char *, size_t))$prefix\_$group_with_empty_name\_in_word_set$atts\};\nif(!len) return &_empty;\nif (len <= MAX_WORD_LENGTH/r;
			}
		}elsif(defined $group_with_empty_name){
			my $atts='';
				if(defined $group_with_empty_name_att){
					$atts=",$group_with_empty_name_att";
				}
			$groups_gperfed="static const struct $prefix\_group *$prefix\_in_word_set (register const char *str, register size_t len){static const struct $prefix\_group _empty=\{\"\",(const struct SET_INI_KEY *(*)(const char *, size_t))$prefix\_$group_with_empty_name\_in_word_set$atts\};\nreturn len?0:&_empty;}";
		}else{
			die;
		}
		#~ print $groups_struct."\n$groups_gperfed\n";
		#~ print "<$total_keys_struct>,\n<$total_onloads>,\n<$total_keys_gperfed>";
		return "$groups_struct\n$total_keys_struct\n$total_onloads\n$total_keys_gperfed\n$groups_gperfed";
	}
	return shift=~s/(^|\W)set::ini_info\s*\(\s*($REGEXP_C_ID)\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._iniinfo($2,$3)/erg;
}

sub iniworks($){
	sub _iniworks{
		return qq{enum SET_INI_TYPE{
	SET_INI_TYPE_SINT64,SET_INI_TYPE_BOOLEAN,SET_INI_TYPE_STRING
};

struct SET_INI_GROUP{
	const char *name;
	const struct SET_INI_KEY *(*in_word_set) (register const char *,
					register size_t);
} __attribute__((packed));

struct SET_INI_KEY{
	const char *name;
	SET_INI_BOOLEAN (*onload) (const struct SET_INI_GROUP *,
			       const struct SET_INI_KEY *,const char *kn, size_t kz,
			       const char *v, size_t vz, SET_INI_INT64 i,
			       enum SET_INI_TYPE t,const void*udata);
} __attribute__((packed));

typedef const struct SET_INI_GROUP*(*SET_INI_GROUP_IN_WORD_SET)(register const char*,register size_t);
enum SET_INI_PARSER_RESULT{
	SET_INI_PARSER_OK,SET_INI_PARSER_CANCELLED,SET_INI_PARSER_UTF8_ERROR
};

typedef SET_INI_BOOLEAN (*SET_INI_REPORT_KEY)(const struct SET_INI_GROUP*g,const char*,size_t,const char*,size_t,const char*,size_t,SET_INI_INT64,enum SET_INI_TYPE,const void*udata);
typedef SET_INI_BOOLEAN (*SET_INI_REPORT_GROUP)(const char*,size_t,const void*udata);

static SET_INI_BOOLEAN set_ini_text_to_int64(const char *t,size_t tz,SET_INI_UINT64 *pi){
	if(tz>20 || !tz)
		return SET_INI_FALSE;
	SET_INI_BOOLEAN sgn;
	const char *e=t+tz;
	if(*t=='-'){
		sgn=SET_INI_TRUE;
		++t;
	}else{
		sgn=SET_INI_FALSE;
	}
	SET_INI_UINT64 s=0;
	for(*pi=0;t<e;++t){
		if(__builtin_mul_overflow(*pi,10,pi) || *t<'0' || *t>'9')
			return SET_INI_FALSE;
		if(__builtin_add_overflow(*pi,*t-'0',pi))
			return SET_INI_FALSE;
	}
	if(sgn){
		if(*pi>0x7fffffffffffffff)
			return SET_INI_FALSE;
		*pi=((SET_INI_INT64)*pi)*-1;
	}
	return SET_INI_TRUE;
}

static const char *set_ini_skip_spaces(const char *s){
	while(*s==' ' || *s=='\\n' || *s=='\\t' || *s=='\\r')++s;
	return s;
}

static SET_INI_BOOLEAN set_ini_skip_utf8(const char **s){
	SET_INI_ASSERT(s && *s && **s);
	if((signed char)**s>0){
		++*s;
		return SET_INI_TRUE;
	}
	if(((**s)&224)==192){
l_back1:if((*(++*s)&192)==128){
			++*s;
			return SET_INI_TRUE;
		}
		return SET_INI_FALSE;
	}
	if(((**s)&240)==224){
l_back2:if((*(++*s)&192)==128){
			goto l_back1;
		}
		return SET_INI_FALSE;
	}
	if(((**s)&248)==240){
		if((*(++*s)&192)==128)
			goto l_back2;
	}
	return SET_INI_FALSE;
}

static SET_INI_BOOLEAN set_ini_till_token_end(const char**s){
	SET_INI_ASSERT(s && *s && **s);
	do{
		if(**s=='=')
			return SET_INI_TRUE;
		if(!set_ini_skip_utf8(s))
			return SET_INI_FALSE;
	}while(**s);
	return SET_INI_TRUE;
}

static SET_INI_BOOLEAN set_ini_till_token_end2(const char**s){
	SET_INI_ASSERT(s && *s && **s);
	do{
		if(**s=='=')
			return SET_INI_TRUE;
		if(!set_ini_skip_utf8(s))
			return SET_INI_FALSE;
	}while(**s && **s!=' ' && **s!='\\n' && **s!='\\t' && **s!='\\r');
	return SET_INI_TRUE;
}

static SET_INI_BOOLEAN set_ini_till_zero_or_char(const char**s,char c){
	SET_INI_ASSERT(s && *s);
	while(**s && **s!=c){
		if(!set_ini_skip_utf8(s))
			return SET_INI_FALSE;
	}
	return SET_INI_TRUE;
}

static SET_INI_BOOLEAN set_ini_do_till_zero(const char**s){
	SET_INI_ASSERT(s && *s);
	do{
		if(!set_ini_skip_utf8(s))
			return SET_INI_FALSE;
	}while(**s);
	return SET_INI_TRUE;
}

static enum SET_INI_PARSER_RESULT set_ini_parse_cmd(
SET_INI_GROUP_IN_WORD_SET get_group,int i,const char*const*v,
SET_INI_REPORT_GROUP report_group,SET_INI_REPORT_KEY report_key,const void*udata){
	SET_INI_ASSERT(get_group && v);
	const struct SET_INI_GROUP *group=get_group(NULL,0);
	const char *group_name="";
	size_t group_name_z=0;
	for(int d=0;d<i;++d){
		const char *s,*kn;
		s=kn=v[d];
		size_t kz;
		switch(*s){
			case 0:continue;
			case '\\'':case '"':{
				char c= *s;
				kn= ++s;
				if(!set_ini_till_zero_or_char(&s,c))
						return SET_INI_PARSER_UTF8_ERROR;
				if(!*s){
					--kn;
					goto l_boolkw;
				}
				kz=s-kn;
				++s;
				if(!*s){
					--kn;
					goto l_boolkw;
				}
				if(*s=='=')
					goto l_equsgn;
				if(!set_ini_do_till_zero(&s))
					return SET_INI_PARSER_UTF8_ERROR;
				--kn;
				goto l_boolkw;
			}
			case '[':{
				const char *ng= ++s;
				if(!set_ini_till_zero_or_char(&s,']'))
						return SET_INI_PARSER_UTF8_ERROR;
				if(*s){
					group_name=ng;
					group_name_z=s-ng;
					if(!(group=get_group(ng,s-ng)) &&
					report_group && !report_group(ng,s-ng,udata))
						return SET_INI_PARSER_CANCELLED;
					break;
				}
				goto l_boolkw;
			}
			default:{
				if(!set_ini_till_token_end(&s))
					return SET_INI_PARSER_UTF8_ERROR;
				if(*s){
					kz=s-kn;
l_equsgn:;			const char *vs= ++s;
					if(*s=='\\'' || *s=='"'){
						char c= *s;
						++vs;
						if(!set_ini_till_zero_or_char(&s,c))
							return SET_INI_PARSER_UTF8_ERROR;
						if(!*s)
							--vs;
					}else if(*s){
						if(!set_ini_do_till_zero(&s))
							return SET_INI_PARSER_UTF8_ERROR;
					}
					const struct SET_INI_KEY*a;
					if(group && (a=group->in_word_set(kn,kz))){
						SET_INI_UINT64 r;
						enum SET_INI_TYPE t=set_ini_text_to_int64(vs,s-vs,&r)?SET_INI_TYPE_SINT64:SET_INI_TYPE_STRING;
						if(!a->onload(group,a,kn,kz,vs,s-vs,r,t,udata))
							return SET_INI_PARSER_CANCELLED;
					}else if(report_key){
						SET_INI_UINT64 r;
						enum SET_INI_TYPE t=set_ini_text_to_int64(vs,s-vs,&r)?SET_INI_TYPE_SINT64:SET_INI_TYPE_STRING;
						if(!report_key(group,group_name,group_name_z,kn,kz,vs,s-vs,r,t,udata))
							return SET_INI_PARSER_CANCELLED;
					}
				}else{
l_boolkw:;			const struct SET_INI_KEY*a;
					if(group && (a=group->in_word_set(kn,s-kn))){
						if(!a->onload(group,a,kn,s-kn,NULL,0,0,SET_INI_TYPE_BOOLEAN,udata))
							return SET_INI_PARSER_CANCELLED;
					}else if(report_key){
						if(!report_key(group,group_name,group_name_z,kn,s-kn,NULL,0,0,SET_INI_TYPE_BOOLEAN,udata))
							return SET_INI_PARSER_CANCELLED;
					}
				}
				break;
			}
		}
	}
	return SET_INI_PARSER_OK;
}

static SET_INI_BOOLEAN set_ini_do_till_zero_or_space(const char**s){
	SET_INI_ASSERT(s && *s);
	do{
		if(**s==' ' || **s=='\\n' || **s=='\\t' || **s=='\\r')
			break;
		if(!set_ini_skip_utf8(s))
			return SET_INI_FALSE;
	}while(**s);
	return SET_INI_TRUE;
}

static enum SET_INI_PARSER_RESULT set_ini_parse_string(
SET_INI_GROUP_IN_WORD_SET get_group,const char *s,
SET_INI_REPORT_GROUP report_group,SET_INI_REPORT_KEY report_key,const void*udata){
	SET_INI_ASSERT(get_group && s);
	const struct SET_INI_GROUP *group=get_group(NULL,0);
	const char *group_name="";
	size_t group_name_z=0;
	while(*(s=set_ini_skip_spaces(s))){
		const char *kn=s;
		size_t kz;
		if(*s=='\\'' || *s=='"'){
			char c= *s;
			++kn;
			++s;
			if(!set_ini_till_zero_or_char(&s,c))
				return SET_INI_PARSER_UTF8_ERROR;
			if(!*s){
				--kn;
				goto l_boolkw;
			}
			kz=s-kn;
			++s;
			if(*s=='=')
				goto l_equsgn;
			if(!set_ini_do_till_zero_or_space(&s))
				return SET_INI_PARSER_UTF8_ERROR;
			--kn;
			goto l_boolkw;
		}else if(*s=='['){
			const char *gn= ++s;
			if(!*s)
				goto l_boolkw;
			if(!set_ini_till_zero_or_char(&s,']'))
				return SET_INI_PARSER_UTF8_ERROR;
			if(!*s)
				goto l_boolkw;
			group_name=gn;
			group_name_z=s-gn;
			if(!(group=get_group(group_name,group_name_z)) && report_group &&
			!report_group(group_name,group_name_z,udata))
				return SET_INI_PARSER_CANCELLED;
			++s;
		}else{
			if(!set_ini_till_token_end2(&s))
				return SET_INI_PARSER_UTF8_ERROR;
			if(*s=='='){
				kz=s-kn;
l_equsgn:;		const char *vs= ++s;
				if(*s=='\\'' || *s=='"'){
					char c= *s;
					++vs;
					++s;
					if(!set_ini_till_zero_or_char(&s,c))
						return SET_INI_PARSER_UTF8_ERROR;
					if(!*s)
						--vs;
				}else if(*s){
					if(!set_ini_do_till_zero_or_space(&s))
						return SET_INI_PARSER_UTF8_ERROR;
				}
				const struct SET_INI_KEY*a;
				if(group && (a=group->in_word_set(kn,kz))){
					SET_INI_UINT64 r;
					enum SET_INI_TYPE t=set_ini_text_to_int64(vs,s-vs,&r)?SET_INI_TYPE_SINT64:SET_INI_TYPE_STRING;
					if(!a->onload(group,a,kn,kz,vs,s-vs,r,t,udata))
						return SET_INI_PARSER_CANCELLED;
				}else if(report_key){
					SET_INI_UINT64 r;
					enum SET_INI_TYPE t=set_ini_text_to_int64(vs,s-vs,&r)?SET_INI_TYPE_SINT64:SET_INI_TYPE_STRING;
					if(!report_key(group,group_name,
					group_name_z,kn,kz,vs,s-vs,r,t,udata))
						return SET_INI_PARSER_CANCELLED;
				}
				if(*s)
					++s;
				else
					break;
			}else{
l_boolkw:;		const struct SET_INI_KEY *a;
				if(group && (a=group->in_word_set(kn,s-kn))){
					if(!a->onload(group,a,kn,s-kn,
					NULL,0,0,SET_INI_TYPE_BOOLEAN,udata))
						return SET_INI_PARSER_CANCELLED;
				}else if(report_key){
					if(!report_key(group,group_name,
					group_name_z,kn,s-kn,NULL,0,0,SET_INI_TYPE_BOOLEAN,udata))
						return SET_INI_PARSER_CANCELLED;
				}
				if(!*s)
					break;
				++s;
			}
		}
	}
	return SET_INI_PARSER_OK;
}
};
	}
	return shift=~s/(^|\W)set::ini_works\s*;/$1._iniworks()/erg;
}

sub _setstack($$$){
		my ($prefix,$cnt_t,$body)=(@_);
		my $regexp_afterdecl=qr/(?:^|\W):afterdecl\s*$REGEXP_NESTED_BRACKETS/;
		my $regexp_append=qr/(?:^|\W):append\s*$REGEXP_NESTED_BRACKETS/;
		my $afterdecl=join('',$body=~/$regexp_afterdecl/g)=~s/^\s*//rg=~s/\s*$//rg;
		my $append=join('',$body=~/$regexp_append/g)=~s/^\s*//rg=~s/\s*$//rg;
		my $type=($body=~s/$regexp_append|$regexp_afterdecl//rg)=~s/^\s*//rg=~s/\s*$//rg;
		return qq{#ifndef SET_STACK_ASSERT
#define SET_STACK_ASSERT(condition)
#endif

#ifndef SET_STACK_LOG_CRITICAL
#define SET_STACK_LOG_CRITICAL(f,args...)
#endif

#ifndef SET_STACK_MALLOC_CRITICAL_ERROR
#define SET_STACK_MALLOC_CRITICAL_ERROR "Не удалось выделить память(%llu).",sizeof(*m)+sizeof(typeof(m->i[0]))*start_queue_length
#endif

#ifndef SET_STACK_LOG_WARNING
#define SET_STACK_LOG_WARNING(f,args...)
#endif

#ifndef SET_STACK_OVERFLOW_WARNING
#define SET_STACK_OVERFLOW_WARNING "Достигнут предел записей(%llu).",(((unsigned long long)1<<(sizeof((*p)->m)-1))|~((unsigned long long)1<<(sizeof((*p)->m)-1)))/(((typeof((*p)->m))-1)<0?2:1)
#endif

#ifndef SET_STACK_REALLOC_CRITICAL_ERROR
#define SET_STACK_REALLOC_CRITICAL_ERROR "Не удалось перераспределить память от %llu до %llu.",sizeof(**p)+sizeof(typeof(n->i[0]))*(*p)->m,sizeof(*n)+sizeof(typeof(n->i[0]))*nm
#endif

struct $prefix\_stack{
	$cnt_t l,m;$append
	$type i[];
}$afterdecl;

static struct $prefix\_stack *$prefix\_stack_new($cnt_t start_queue_length){
	SET_STACK_ASSERT(start_queue_length>0);
	struct $prefix\_stack *m=SET_STACK_MALLOC(sizeof(*m)+sizeof(typeof(m->i[0]))*start_queue_length);
	if(!m){
		SET_STACK_LOG_CRITICAL(SET_STACK_MALLOC_CRITICAL_ERROR);
		return NULL;
	}
	m->l=0;
	m->m=start_queue_length;
	return m;
}

enum $prefix\_stack_occupy_result{
	$prefix\_stack_occupy_ok, $prefix\_stack_occupy_overflow,$prefix\_stack_occupy_realloc_error
};
static enum $prefix\_stack_occupy_result $prefix\_stack_occupy(struct $prefix\_stack**p,$cnt_t amount){
	SET_STACK_ASSERT(p && *p && amount>0);
	$cnt_t nl;
	if(__builtin_add_overflow((*p)->l,amount,&nl)){
		SET_STACK_LOG_WARNING(SET_STACK_OVERFLOW_WARNING);
		return $prefix\_stack_occupy_overflow;
	}
	$cnt_t nm= (*p)->m;
	if(nl>nm){
		while(nl>nm){
			if(__builtin_mul_overflow(nm,2,&nm)){
				nm= ((1<<(sizeof((*p)->m)-1))|~(1<<(sizeof((*p)->m)-1)))/(((typeof((*p)->m))-1)<0?2:1);
				break;
			}
		}
		struct $prefix\_stack *n=SET_STACK_REALLOC(*p,sizeof(*n)+sizeof(typeof(n->i[0]))*nm);
		if(!n){
			SET_STACK_LOG_CRITICAL(SET_STACK_REALLOC_CRITICAL_ERROR);
			return $prefix\_stack_occupy_realloc_error;
		}
		n->m=nm;
		*p=n;
	}
	(*p)->l=nl;
	return $prefix\_stack_occupy_ok;
}
static enum $prefix\_stack_occupy_result $prefix\_stack_push(struct $prefix\_stack**p,typeof(((struct $prefix\_stack*)0)->i[0]) v){
	SET_STACK_ASSERT(p && *p);
	enum $prefix\_stack_occupy_result e=$prefix\_stack_occupy(p,1);
	if(e==$prefix\_stack_occupy_ok)
		(*p)->i[(*p)->l-1]=v;
	return e;
}
static typeof(((struct $prefix\_stack*)0)->i[0]) $prefix\_stack_pop(struct $prefix\_stack*s){
	SET_STACK_ASSERT(s && s->l>0);
	return s->i[--(s->l)];
}
static void $prefix\_stack_free(struct $prefix\_stack*s){
	SET_STACK_ASSERT(s);
	SET_STACK_FREE(s);
}
};
}

sub setstack($){
	return shift=~s/(^|\W)set::stack\s*\(\s*($REGEXP_C_ID)\s*,\s*((?:$REGEXP_C_ID\s*){1,3})\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._setstack($2,$3,$4)/erg;
}

sub setlist($){
	sub _setlist($$$){
		my ($prefix,$cnt_t,$body)=(@_);
		#~ print "PREFIX: $prefix, CNTTYPE: $cnt_t, BODY: <$body>\n";
		my $type=($body=~s/(?:^|\W)append\s*$REGEXP_NESTED_BRACKETS//rg)=~s/^\s*//rg=~s/\s*$//rg;
		#~ print "TYPE: <$type>\n";
		my $esctype=$type=~s/\{/\\{/rg=~s/\}/\\}/rg=~s/\*/\\*/rg;
		#~ print "ESCTYPE: <$esctype>\n";
		$body=$body=~s/$esctype/struct{int set;$cnt_t prev,next,prev_empty,next_empty;$type}/r;
		#~ print "BODY: <$body>\n";
		my $itemname=($type=~/($REGEXP_C_ID)\s*;\s*$/)[0];
		my $stack_base=_setstack("$prefix",$cnt_t,$body."\nappend{$cnt_t first,last,first_empty,last_empty;}");
		return $stack_base.qq{static struct $prefix\_stack *$prefix\_list_new($cnt_t start_queue_length){
	SET_STACK_ASSERT(start_queue_length>0);
	struct $prefix\_stack *s=$prefix\_stack_new(start_queue_length);
	if(s){
		s->first_empty=0;
		s->last_empty=s->m-1;
		for($cnt_t i=0;i<s->m-1;++i){
			s->i[i].set=!!0;
			s->i[i].next_empty=i+1;
			s->i[i+1].prev_empty=i;
		}
		s->i[s->m-1].set=!!0;
	}
	return s;
}
static enum $prefix\_stack_occupy_result $prefix\_list_append(struct $prefix\_stack**p,typeof(((struct $prefix\_stack*)0)->i[0].$itemname) v){
	SET_STACK_ASSERT(p && *p);
	$cnt_t om=(*p)->m;
	enum $prefix\_stack_occupy_result e=$prefix\_stack_occupy(p,1);
	if(e!=$prefix\_stack_occupy_ok)
		return e;
	if(om!=(*p)->m){
		(*p)->last_empty=(*p)->m-1;
		(*p)->first_empty=om;
		for($cnt_t i=om;i<(*p)->m-1;++i){
			(*p)->i[i].set=!!0;
			(*p)->i[i].next_empty=i+1;
			(*p)->i[i+1].prev_empty=i;
		}
		(*p)->i[(*p)->m-1].set=!!0;
	}
	if((*p)->l!=1){
		(*p)->i[(*p)->last_empty].prev=(*p)->last;
		(*p)->i[(*p)->last].next=(*p)->last_empty;
		(*p)->i[(*p)->last=(*p)->last_empty].$itemname=v;
	}else{
		(*p)->i[(*p)->last=(*p)->first=(*p)->last_empty].$itemname=v;
	}
	(*p)->i[(*p)->last].set=!0;
	if((*p)->first_empty!=(*p)->last_empty){
		(*p)->last_empty=(*p)->i[(*p)->last_empty].prev_empty;
	}
	return $prefix\_stack_occupy_ok;
}
void $prefix\_list_remove(struct $prefix\_stack*s,$cnt_t i){
	SET_STACK_ASSERT(s && i<s->m);
	if(s->l>0 && s->i[i].set){
		if(s->first==i && i==s->last){
		}else if(s->first==i){
			s->first=s->i[s->first].next;
		}else if(s->last==i){
			s->last=s->i[s->last].prev;
		}else{
			s->i[s->i[i].prev].next=s->i[i].next;
			s->i[s->i[i].next].prev=s->i[i].prev;
		}
		if(s->l!=s->m){
			s->i[s->last_empty].next_empty=i;
			s->i[i].prev_empty=s->last_empty;
		}else{
			s->first_empty=i;
		}
		s->last_empty=i;
		s->i[i].set=!!0;
		s->l--;
	}
}
};
	}
	return shift=~s/(^|\W)set::list\s*\(\s*($REGEXP_C_ID)\s*,\s*((?:$REGEXP_C_ID\s*){1,3})\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._setlist($2,$3,$4)/erg;
}

sub setarchive($){
	sub _setarchive($$$){
		my ($prefix,$arcfile,$body)=(@_);
		$arcfile=$arcfile=~s/\\"/"/rg;
		open my $arcfh,'>',$arcfile or die;
		my $arcinidata='';
		my $arcoffs=0;
		my $arciniinfo="set::ini_info($prefix){\n";
		my $firstgroup;
		my $enums="enum $prefix\_records{";
		my $n_records=0;
		while($body=~/($REGEXP_C_ID)\s*\(\s*((?:"(?:\\"|[^"])*"\s*))\)\s*;/g){
			my ($subprefix,$files)=($1,$2);
			my $totdata='';
			while($files=~/"((?:\\"|[^"])*)"/g){
				my $td=slurpfile($current_script_dir.($1=~s/\\"/"/rg));
				die if not length($td);
				$totdata.=$td;
			}
			my $comptot=exomod("darc",$totdata);
			if(length($totdata)/length($comptot)<1.5){
				print "set::archive::$prefix\::$subprefix 100%\n";
				print $arcfh $totdata;
				$arcinidata.="[$subprefix]\noffset=$arcoffs\nsize=".length($totdata)."\n";
				$arcoffs+=length($totdata);
			}else{
				print "set::archive::$prefix\::$subprefix ".(length($comptot)/(length($totdata)/100))."%\n";
				print $arcfh $comptot;
				$arcinidata.="[$subprefix]\noffset=$arcoffs\nsize=".length($comptot)."\nesize=".length($totdata)."\n";
				$arcoffs+=length($comptot);
			}
			if(defined $firstgroup){
				$arciniinfo.=qq#$subprefix\{
	names "$subprefix"
	declfrom "$firstgroup"
	atts ".$firstgroup={$prefix\_$subprefix\_record}"
	keysfrom "$firstgroup"
}
#;
			}else{
				$firstgroup=$subprefix;
				$arciniinfo.=qq#$subprefix\{
	names "$subprefix"
	decl "enum $prefix\_records id;"
	atts ".$firstgroup={$prefix\_$subprefix\_record}"
	keys{
		koffset{
			names "offset"
			onload{
				if(t==SET_INI_TYPE_SINT64){
					((struct SET_ARCHIVE_RECORD*)udata)[g->$firstgroup.id].offset=i;
					return SET_INI_TRUE;
				}
				SET_ARCHIVE_LOG_ERROR("set::archive::$prefix %s:%.*s",g->name,(int)kz,kn);
				return SET_INI_FALSE;
			}
		}
		ksize{
			names "size"
			onload{
				if(t==SET_INI_TYPE_SINT64){
					((struct SET_ARCHIVE_RECORD*)udata)[g->$firstgroup.id].size=i;
					return SET_INI_TRUE;
				}
				SET_ARCHIVE_LOG_ERROR("set::archive::$prefix %s:%.*s",g->name,(int)kz,kn);
				return SET_INI_FALSE;
			}
		}
		kesize{
			names "esize"
			onload{
				if(t==SET_INI_TYPE_SINT64){
					((struct SET_ARCHIVE_RECORD*)udata)[g->$firstgroup.id].esize=i;
					return SET_INI_TRUE;
				}
				SET_ARCHIVE_LOG_ERROR("set::archive::$prefix %s:%.*s",g->name,(int)kz,kn);
				return SET_INI_FALSE;
			}
		}
	}
}
#;
			}
			$enums.="\n\t$prefix\_$subprefix\_record,";
			$n_records++;
		}
		$enums.="\n\t$prefix\_length\n};";
		#~ $enums=substr($enums,0,-1)."\n};";
		$arciniinfo.="}";
		#~ print "$enums\n$arciniinfo\n";
		overfile("$prefix\.ini",$arcinidata);
		close($arcfh) or die;
		return "$enums\n".iniinfo($arciniinfo);
	}
	return shift=~s/(^|\W)set::archive\s*\(\s*($REGEXP_C_ID)\s*,\s*"((?:\\"|[^"])*)"\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._setarchive($2,$3,$4)/erg;
}

#~ sub archiveworks($){
	#~ sub _archiveworks{
		#~ return qq{struct SET_ARCHIVE_RECORD{
	#~ SET_INI_INT64 offset;
	#~ size_t size;
	#~ size_t esize;
#~ };

#~ #ifdef SET_ARCHIVE_SDL
#~ static void set_archive_reset_records(struct SET_ARCHIVE_RECORD*r,int n){
	#~ for(int i=0;i<n;++i){
		#~ r->offset= -1;
		#~ r->esize=r->size=0;
	#~ }
#~ }
#~ static SET_INI_BOOLEAN set_archive_check_records(struct SET_ARCHIVE_RECORD*r,int n){
	#~ for(int i=0;i<n;++i){
		#~ SDL_assert_always("Неполная или повреждённая запись." && r->offset!=-1 && r->size);
		#~ if(r->offset==-1 || r->size==0)
			#~ return SET_INI_FALSE;
	#~ }
	#~ return SET_INI_TRUE;
#~ }
#~ static SET_INI_BOOLEAN set_archive_init_records_from_file_sdl(const char *inifile,
#~ SET_INI_GROUP_IN_WORD_SET get_group,SET_INI_REPORT_GROUP report_group,
#~ SET_INI_REPORT_KEY report_key,struct SET_ARCHIVE_RECORD*udata){
	#~ SDL_assert(inifile && *inifile && get_group && udata);
	#~ SDL_RWops *r=SDL_RWFromFile(inifile,"rb");
	#~ if(!r){
		#~ SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
		#~ return SET_INI_FALSE;
	#~ }
	#~ Sint64 len=SDL_RWsize(r);
	#~ if(len<0){
		#~ SET_ARCHIVE_LOG_ERROR("Не удалось определить размер файла '%s' (%s).",inifile,SDL_GetError());
		#~ SDL_RWclose(r);
		#~ return SET_INI_FALSE;
	#~ }
	#~ typeof(len) nl;
	#~ if(__builtin_add_overflow(len,1,&nl)||
		#~ nl>(((size_t)1<<(sizeof(size_t)*8-1))|~((size_t)1<<(sizeof(size_t)*8-1)))/((size_t)-1<0?2:1)){
		#~ SET_ARCHIVE_LOG_ERROR("Не получится выделить память под файл '%s'.",inifile);
		#~ SDL_RWclose(r);
		#~ return SET_INI_FALSE;
	#~ }
	#~ char *m=SET_ARCHIVE_MALLOC(len+1);
	#~ if(!m){
		#~ SET_ARCHIVE_LOG_CRITICAL("Не удалось выделить память под файл '%s'.",inifile);
		#~ SDL_RWclose(r);
		#~ return SET_INI_FALSE;
	#~ }
	#~ if(SDL_RWread(r,m,1,len)!=len){
		#~ SET_ARCHIVE_LOG_ERROR("Не удалось прочитать файл '%s' (%s).",inifile,SDL_GetError());
		#~ SET_ARCHIVE_FREE(m);
		#~ SDL_RWclose(r);
		#~ return SET_INI_FALSE;
	#~ }
	#~ char *s=m;
	#~ m[len]='\\0';
	#~ if(len>=3){
		#~ if((Uint8)m[0]==0xef && (Uint8)m[1]==0xbb && (Uint8)m[2]==0xbf)
			#~ s+=3;
	#~ }
	#~ SDL_RWclose(r);
	#~ switch(set_ini_parse_string(get_group,s,report_group,report_key,udata)){
		#~ case SET_INI_PARSER_OK:break;
		#~ case SET_INI_PARSER_CANCELLED:{
			#~ SET_ARCHIVE_FREE(m);
			#~ return SET_INI_FALSE;
		#~ }
		#~ case SET_INI_PARSER_UTF8_ERROR:{
			#~ SET_ARCHIVE_LOG_ERROR("Ошибка кодировки UTF-8 файла '%s'.",inifile);
			#~ SET_ARCHIVE_FREE(m);
			#~ return SET_INI_FALSE;
		#~ }
	#~ }
	#~ SET_ARCHIVE_FREE(m);
	#~ return SET_INI_TRUE;
#~ }
#~ static Uint8 *set_archive_load_record_sdl(SDL_RWops *rw,struct SET_ARCHIVE_RECORD *r){
	#~ SDL_assert(rw && r);
	#~ SDL_assert_always("Повреждённая запись." && r->size>0);
	#~ if(r->size<=0)
		#~ return NULL;
	#~ if(SDL_RWseek(rw,r->offset,RW_SEEK_SET)<0){
		#~ SET_ARCHIVE_LOG_ERROR("Ошибка при перемещению по файлу (%s)",SDL_GetError());
		#~ return NULL;
	#~ }
	#~ typeof(r->size) nsz;
	#~ if(__builtin_add_overflow(r->size,1,&nsz)){
		#~ SET_ARCHIVE_LOG_ERROR("Размер записи слишком большой.");
		#~ return NULL;
	#~ }
	#~ Uint8 *idat=SET_ARCHIVE_MALLOC(nsz);
	#~ Uint8 *edat;
	#~ if(!idat){
		#~ SET_ARCHIVE_LOG_CRITICAL("Не удалось выделить память.");
		#~ return NULL;
	#~ }
	#~ if(SDL_RWread(rw,idat,1,r->size)!=r->size){
		#~ SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
		#~ SET_ARCHIVE_FREE(idat);
		#~ return NULL;
	#~ }
	#~ if(!r->esize){
		#~ idat[r->size]='\\0';
		#~ return idat;
	#~ }
	#~ typeof(r->esize) nesz;
	#~ if(__builtin_add_overflow(r->esize,1,&nesz)){
		#~ SET_ARCHIVE_LOG_ERROR("После распаковки файл получится слишком большим.");
		#~ SET_ARCHIVE_FREE(idat);
		#~ return NULL;
	#~ }
	#~ edat=SET_ARCHIVE_MALLOC(nesz);
	#~ if(!edat){
		#~ SET_ARCHIVE_LOG_ERROR("Не удалось выделить память.");
		#~ SET_ARCHIVE_FREE(idat);
		#~ return NULL;
	#~ }
	#~ uLongf dstlen=r->esize;
	#~ switch(uncompress(edat,&dstlen,idat,r->size)){
		#~ case Z_OK:break;
		#~ case Z_MEM_ERROR:{
			#~ SET_ARCHIVE_LOG_ERROR("Недостаточно памяти.");
			#~ SET_ARCHIVE_FREE(edat);
			#~ SET_ARCHIVE_FREE(idat);
			#~ return NULL;
		#~ }
		#~ case Z_BUF_ERROR:{
			#~ SET_ARCHIVE_LOG_ERROR("Размер данных оказался больше указанного.");
			#~ SET_ARCHIVE_FREE(edat);
			#~ SET_ARCHIVE_FREE(idat);
			#~ return NULL;
		#~ }
		#~ case Z_DATA_ERROR:{
			#~ SET_ARCHIVE_LOG_ERROR("Входящие данные испорчены или имеют неверный размер.");
			#~ SET_ARCHIVE_FREE(edat);
			#~ SET_ARCHIVE_FREE(idat);
			#~ return NULL;
		#~ }
	#~ }
	#~ SET_ARCHIVE_FREE(idat);
	#~ edat[r->esize]='\\0';
	#~ return edat;
#~ }
#~ static SDL_Texture *set_archive_load_texture(SDL_RWops *rw,SDL_Renderer*renderer,struct SET_ARCHIVE_RECORD *r,int *w,int *h){
	#~ SDL_assert(rw && r);
	#~ Uint8 *m=set_archive_load_record_sdl(rw,r);
	#~ if(m){
		#~ SDL_RWops *o=SDL_RWFromConstMem(m,r->esize?r->esize:r->size);
		#~ if(!o){
			#~ SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
			#~ SET_ARCHIVE_FREE(m);
			#~ return NULL;
		#~ }
		#~ SDL_Surface *sur=IMG_Load_RW(o,1);
		#~ if(!sur){
			#~ SET_ARCHIVE_LOG_ERROR("%s.",IMG_GetError());
			#~ SET_ARCHIVE_FREE(m);
			#~ return NULL;
		#~ }
		#~ SDL_Texture *t=SDL_CreateTextureFromSurface(renderer,sur);
		#~ if(!t){
			#~ SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
			#~ SDL_FreeSurface(sur);
			#~ SET_ARCHIVE_FREE(m);
			#~ return NULL;
		#~ }
		#~ if(w)
			#~ *w=sur->w;
		#~ if(h)
			#~ *h=sur->h;
		#~ SDL_FreeSurface(sur);
		#~ SET_ARCHIVE_FREE(m);
		#~ return t;
	#~ }
	#~ return NULL;
#~ }
#~ static Mix_Music *set_archive_load_music(SDL_RWops *rw,struct SET_ARCHIVE_RECORD *r,Uint8**pdata){
	#~ SDL_assert(rw && pdata);
	#~ Uint8 *m=set_archive_load_record_sdl(rw,r);
	#~ if(m){
		#~ SDL_RWops *o=SDL_RWFromConstMem(m,r->esize?r->esize:r->size);
		#~ if(!o){
			#~ SET_ARCHIVE_LOG_ERROR("%s",SDL_GetError());
			#~ SET_ARCHIVE_FREE(m);
			#~ return NULL;
		#~ }
		#~ Mix_Music *mus=Mix_LoadMUS_RW(o,1);
		#~ if(!mus){
			#~ SET_ARCHIVE_LOG_ERROR("%s",Mix_GetError());
			#~ SET_ARCHIVE_FREE(m);
		#~ }
		#~ *pdata=m;
		#~ return mus;
	#~ }
	#~ return NULL;
#~ }
#~ #ifdef SET_ARCHIVE_BOXY4
#~ static struct boxyheader*set_archive_loadboxy(SDL_RWops*rw,
#~ struct SET_ARCHIVE_RECORD *r){
	#~ SDL_assert_always("Запись не является файлом с хитбоксами." && ((r->esize && r->esize>=sizeof(struct boxyheader))||
	#~ (!r->esize && r->size>=sizeof(struct boxyheader))));
	#~ if((r->esize && r->esize<sizeof(struct boxyheader))||
	#~ (!r->esize && r->size<sizeof(struct boxyheader)))
		#~ return NULL;
	#~ struct boxyheader*m=(typeof(m))set_archive_load_record_sdl(rw,r);
	#~ if(m){
		#~ SDL_assert_always("Запись не является файлом с хитбоксами." &&
		#~ m->magic[0]=='B' && m->magic[1]=='O' && m->magic[2]=='X' && m->magic[3]=='Y' &&
		#~ m->magic[4]=='4' && m->magic[5]=='L' && m->magic[6]=='O' && m->magic[7]=='E');
		#~ if(m->magic[0]!='B' || m->magic[1]!='O' || m->magic[2]!='X' || m->magic[3]!='Y' ||
		#~ m->magic[4]!='4' || m->magic[5]!='L' || m->magic[6]!='O' || m->magic[7]!='E'){
			#~ SDL_free(m);
			#~ return NULL;
		#~ }
		#~ if((m->bigendian && SDL_BYTEORDER!=SDL_BIG_ENDIAN)||
			#~ (!m->bigendian && SDL_BYTEORDER!=SDL_LIL_ENDIAN)){
			#~ #define swap16(x) ((x<<8)|(x>>8))
			#~ m->n_frames=swap16(m->n_frames);
			#~ for(typeof(m->n_frames) oi=0;oi<m->n_frames;++m->n_frames){
				#~ #define swap32(x) ((x<<24)|(x>>24)|((x<<8)&0xff0000)|((x>>8)&0xff00))
				#~ m->offsets[oi]=swap32(m->offsets[oi]);
				#~ #undef swap32
				#~ struct hitboxes*hb=(typeof(hb))(((Uint8*)m)+sizeof(*m)+
					#~ sizeof(m->offsets[0])*m->n_frames+m->offsets[oi]);
				#~ hb->n_boxes=swap16(hb->n_boxes);
				#~ hb->frame.x=swap16(hb->frame.x);
				#~ hb->frame.y=swap16(hb->frame.y);
				#~ hb->frame.w=swap16(hb->frame.w);
				#~ hb->frame.h=swap16(hb->frame.h);
				#~ hb->lazy.x=swap16(hb->lazy.x);
				#~ hb->lazy.y=swap16(hb->lazy.y);
				#~ hb->lazy.w=swap16(hb->lazy.w);
				#~ hb->lazy.h=swap16(hb->lazy.h);
				#~ for(typeof(hb->n_boxes) bi=0;bi<hb->n_boxes;++bi){
					#~ hb->box[bi].x=swap16(hb->box[bi].x);
					#~ hb->box[bi].y=swap16(hb->box[bi].y);
					#~ hb->box[bi].w=swap16(hb->box[bi].w);
					#~ hb->box[bi].h=swap16(hb->box[bi].h);
				#~ }
			#~ }
			#~ #undef swap16
		#~ }
	#~ }
	#~ return m;
#~ }
#~ #endif //SET_ARCHIVE_BOXY4
#~ #endif //SET_ARCHIVE_SDL
#~ };
	#~ }
	#~ return shift=~s/(^|\W)set::archive_works\s*;/$1._archiveworks()/erg;
#~ }
sub archiveworks($){
	sub _archiveworks{
		return qq{struct SET_ARCHIVE_RECORD{
	SET_INI_INT64 offset;
	size_t size;
	size_t esize;
};

static void set_archive_reset_records(struct SET_ARCHIVE_RECORD*r,int n){
	for(int i=0;i<n;++i){
		r->offset= -1;
		r->esize=r->size=0;
	}
}
static SET_INI_BOOLEAN set_archive_check_records(struct SET_ARCHIVE_RECORD*r,int n){
	for(int i=0;i<n;++i){
		SDL_assert_always("Неполная или повреждённая запись." && r->offset!=-1 && r->size);
		if(r->offset==-1 || r->size==0)
			return SET_INI_FALSE;
	}
	return SET_INI_TRUE;
}
static SET_INI_BOOLEAN set_archive_init_records_from_file_sdl(const char *inifile,
SET_INI_GROUP_IN_WORD_SET get_group,SET_INI_REPORT_GROUP report_group,
SET_INI_REPORT_KEY report_key,struct SET_ARCHIVE_RECORD*udata){
	SDL_assert(inifile && *inifile && get_group && udata);
	SDL_RWops *r=SDL_RWFromFile(inifile,"rb");
	if(!r){
		SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
		return SET_INI_FALSE;
	}
	Sint64 len=SDL_RWsize(r);
	if(len<0){
		SET_ARCHIVE_LOG_ERROR("Не удалось определить размер файла '%s' (%s).",inifile,SDL_GetError());
		SDL_RWclose(r);
		return SET_INI_FALSE;
	}
	typeof(len) nl;
	if(__builtin_add_overflow(len,1,&nl)||
		nl>(((size_t)1<<(sizeof(size_t)*8-1))|~((size_t)1<<(sizeof(size_t)*8-1)))/((size_t)-1<0?2:1)){
		SET_ARCHIVE_LOG_ERROR("Не получится выделить память под файл '%s'.",inifile);
		SDL_RWclose(r);
		return SET_INI_FALSE;
	}
	char *m=SET_ARCHIVE_MALLOC(len+1);
	if(!m){
		SET_ARCHIVE_LOG_CRITICAL("Не удалось выделить память под файл '%s'.",inifile);
		SDL_RWclose(r);
		return SET_INI_FALSE;
	}
	if(SDL_RWread(r,m,1,len)!=len){
		SET_ARCHIVE_LOG_ERROR("Не удалось прочитать файл '%s' (%s).",inifile,SDL_GetError());
		SET_ARCHIVE_FREE(m);
		SDL_RWclose(r);
		return SET_INI_FALSE;
	}
	char *s=m;
	m[len]='\\0';
	if(len>=3){
		if((Uint8)m[0]==0xef && (Uint8)m[1]==0xbb && (Uint8)m[2]==0xbf)
			s+=3;
	}
	SDL_RWclose(r);
	switch(set_ini_parse_string(get_group,s,report_group,report_key,udata)){
		case SET_INI_PARSER_OK:break;
		case SET_INI_PARSER_CANCELLED:{
			SET_ARCHIVE_FREE(m);
			return SET_INI_FALSE;
		}
		case SET_INI_PARSER_UTF8_ERROR:{
			SET_ARCHIVE_LOG_ERROR("Ошибка кодировки UTF-8 файла '%s'.",inifile);
			SET_ARCHIVE_FREE(m);
			return SET_INI_FALSE;
		}
	}
	SET_ARCHIVE_FREE(m);
	return SET_INI_TRUE;
}
static Uint8 *set_archive_load_record_sdl(SDL_RWops *rw,struct SET_ARCHIVE_RECORD *r){
	SDL_assert(rw && r);
	SDL_assert_always("Повреждённая запись." && r->size>0);
	if(r->size<=0)
		return NULL;
	if(SDL_RWseek(rw,r->offset,RW_SEEK_SET)<0){
		SET_ARCHIVE_LOG_ERROR("Ошибка при перемещению по файлу (%s)",SDL_GetError());
		return NULL;
	}
	typeof(r->size) nsz;
	if(__builtin_add_overflow(r->size,1,&nsz)){
		SET_ARCHIVE_LOG_ERROR("Размер записи слишком большой.");
		return NULL;
	}
	Uint8 *idat=SET_ARCHIVE_MALLOC(nsz);
	Uint8 *edat;
	if(!idat){
		SET_ARCHIVE_LOG_CRITICAL("Не удалось выделить память.");
		return NULL;
	}
	if(SDL_RWread(rw,idat,1,r->size)!=r->size){
		SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
		SET_ARCHIVE_FREE(idat);
		return NULL;
	}
	if(!r->esize){
		idat[r->size]='\\0';
		return idat;
	}
	typeof(r->esize) nesz;
	if(__builtin_add_overflow(r->esize,1,&nesz)){
		SET_ARCHIVE_LOG_ERROR("После распаковки файл получится слишком большим.");
		SET_ARCHIVE_FREE(idat);
		return NULL;
	}
	edat=SET_ARCHIVE_MALLOC(nesz);
	if(!edat){
		SET_ARCHIVE_LOG_ERROR("Не удалось выделить память.");
		SET_ARCHIVE_FREE(idat);
		return NULL;
	}
	uLongf dstlen=r->esize;
	switch(uncompress(edat,&dstlen,idat,r->size)){
		case Z_OK:break;
		case Z_MEM_ERROR:{
			SET_ARCHIVE_LOG_ERROR("Недостаточно памяти.");
			SET_ARCHIVE_FREE(edat);
			SET_ARCHIVE_FREE(idat);
			return NULL;
		}
		case Z_BUF_ERROR:{
			SET_ARCHIVE_LOG_ERROR("Размер данных оказался больше указанного.");
			SET_ARCHIVE_FREE(edat);
			SET_ARCHIVE_FREE(idat);
			return NULL;
		}
		case Z_DATA_ERROR:{
			SET_ARCHIVE_LOG_ERROR("Входящие данные испорчены или имеют неверный размер.");
			SET_ARCHIVE_FREE(edat);
			SET_ARCHIVE_FREE(idat);
			return NULL;
		}
	}
	SET_ARCHIVE_FREE(idat);
	edat[r->esize]='\\0';
	return edat;
}
static SDL_Texture *set_archive_load_texture(SDL_RWops *rw,SDL_Renderer*renderer,struct SET_ARCHIVE_RECORD *r,int *w,int *h){
	SDL_assert(rw && r);
	Uint8 *m=set_archive_load_record_sdl(rw,r);
	if(m){
		SDL_RWops *o=SDL_RWFromConstMem(m,r->esize?r->esize:r->size);
		if(!o){
			SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
			SET_ARCHIVE_FREE(m);
			return NULL;
		}
		SDL_Surface *sur=IMG_Load_RW(o,1);
		if(!sur){
			SET_ARCHIVE_LOG_ERROR("%s.",IMG_GetError());
			SET_ARCHIVE_FREE(m);
			return NULL;
		}
		SDL_Texture *t=SDL_CreateTextureFromSurface(renderer,sur);
		if(!t){
			SET_ARCHIVE_LOG_ERROR("%s.",SDL_GetError());
			SDL_FreeSurface(sur);
			SET_ARCHIVE_FREE(m);
			return NULL;
		}
		if(w)
			*w=sur->w;
		if(h)
			*h=sur->h;
		SDL_FreeSurface(sur);
		SET_ARCHIVE_FREE(m);
		return t;
	}
	return NULL;
}
static Mix_Music *set_archive_load_music(SDL_RWops *rw,struct SET_ARCHIVE_RECORD *r,Uint8**pdata){
	SDL_assert(rw && pdata);
	Uint8 *m=set_archive_load_record_sdl(rw,r);
	if(m){
		SDL_RWops *o=SDL_RWFromConstMem(m,r->esize?r->esize:r->size);
		if(!o){
			SET_ARCHIVE_LOG_ERROR("%s",SDL_GetError());
			SET_ARCHIVE_FREE(m);
			return NULL;
		}
		Mix_Music *mus=Mix_LoadMUS_RW(o,1);
		if(!mus){
			SET_ARCHIVE_LOG_ERROR("%s",Mix_GetError());
			SET_ARCHIVE_FREE(m);
		}
		*pdata=m;
		return mus;
	}
	return NULL;
}
static struct boxyheader*set_archive_loadboxy(SDL_RWops*rw,
struct SET_ARCHIVE_RECORD*r){
	SDL_assert_always("Запись не является файлом с хитбоксами." && ((r->esize && r->esize>sizeof(struct boxyheader))||
	(!r->esize && r->size>sizeof(struct boxyheader))));
	if((r->esize && r->esize<=sizeof(struct boxyheader))||
	(!r->esize && r->size<=sizeof(struct boxyheader)))
		return NULL;
	struct boxyheader*m=(typeof(m))set_archive_load_record_sdl(rw,r);
	if(!m)
		return NULL;
	SDL_assert_always("Запись не является файлом с хитбоксами." &&
		m->magic[0]=='B' && m->magic[1]=='O' && m->magic[2]=='X' && m->magic[3]=='Y' &&
		m->magic[4]=='L' && m->magic[5]=='O' && m->magic[6]=='E' && m->magic[7]=='5');
	if(m->magic[0]!='B' || m->magic[1]!='O' || m->magic[2]!='X' || m->magic[3]!='Y' ||
		m->magic[4]!='L' || m->magic[5]!='O' || m->magic[6]!='E' || m->magic[7]!='5')
		return NULL;
	if((m->bigendian && SDL_BYTEORDER!=SDL_BIG_ENDIAN)||
		(!m->bigendian && SDL_BYTEORDER!=SDL_LIL_ENDIAN)){
#define set_archive_loadboxy_swap32(x) x=(((Uint32)x>>24)|((Uint32)x<<24)|(((Uint32)x>>8)&0xff00)|(((Uint32)x<<8)&0xff0000))
#define set_archive_loadboxy_swap64(x) x=(((Uint64)x>>56)|((Uint64)x>>56)|(((Uint64)x>>40)&0xff00)|(((Uint64)x<<40)&0xff000000000000)|(((Uint64)x>>24)&0xff0000)|(((Uint64)x<<24)&0xff0000000000)|(((Uint64)x>>8)&0xff000000)|(((Uint64)x<<8)&0xff00000000))
		set_archive_loadboxy_swap32(m->width);
		set_archive_loadboxy_swap32(m->height);
		set_archive_loadboxy_swap64(m->n_frames);
		for(Uint64 o=0;o<m->n_frames;++o){
			set_archive_loadboxy_swap64(m->offsets[o]);
			struct boxyhitboxes *hb=(typeof(hb))((Uint8*)m+m->offsets[o]+sizeof(struct boxyheader)+sizeof(typeof(((struct boxyheader*)0)->offsets[0]))*m->n_frames);
			set_archive_loadboxy_swap64(hb->n_boxes);
			set_archive_loadboxy_swap32(hb->frame.x);
			set_archive_loadboxy_swap32(hb->frame.y);
			set_archive_loadboxy_swap32(hb->frame.w);
			set_archive_loadboxy_swap32(hb->frame.h);
			set_archive_loadboxy_swap32(hb->lazy.x);
			set_archive_loadboxy_swap32(hb->lazy.y);
			set_archive_loadboxy_swap32(hb->lazy.w);
			set_archive_loadboxy_swap32(hb->lazy.h);
			for(Uint64 b=0;b<hb->n_boxes;++b){
				set_archive_loadboxy_swap32(hb->boxes[b].x);
				set_archive_loadboxy_swap32(hb->boxes[b].y);
				set_archive_loadboxy_swap32(hb->boxes[b].w);
				set_archive_loadboxy_swap32(hb->boxes[b].h);
#undef set_archive_loadboxy_swap64
#undef set_archive_loadboxy_swap32
			}
		}
	}
	return m;
}
};
	}
	return shift=~s/(^|\W)set::archive_works\s*;/$1._archiveworks()/erg;
}

my %loestorage=();
sub _loestore($$){
	my ($id,$body)=(@_);
	warn "loestorage: '$id' переопределяется." if defined $loestorage{$id};
	$loestorage{$id}=$body;
	return '';
}

sub loestore($){
	return shift=~s/(^|\W)loe::store\s*\(\s*($REGEXP_C_ID)\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._loestore($2,$3)/erg;
}

sub loespawn($){
	sub _loespawn($){
		my $id=shift;
		die "loespawn: Нет описания '$id'." if not defined $loestorage{$id};
		return $loestorage{$id};
	}
	return shift=~s/(^|\W)loe::spawn\s*\(\s*($REGEXP_C_ID)\s*\)\s*;/$1._loespawn($2)/erg;
}

sub loestack_get_tokens($){
	my $b=shift;
	my %d=();
	$d{afterstruct}=($b=~/::afterstruct\s*$REGEXP_NESTED_BRACKETS\s*;/)[0] // '';
	$d{hidestruct}=$b=~/::hidestruct\s*;/;
	$d{hideenum}=$b=~/::hideenum\s*;/;
	@{$d{storestruct}}=$b=~/::storestruct\s*$REGEXP_NESTED_BRACKETS\s*;/g;
	@{$d{storeenum}}=$b=~/::storeenum\s*$REGEXP_NESTED_BRACKETS\s*;/g;
	@{$d{storenonstatic}}=$b=~/::storenonstatic\s*$REGEXP_NESTED_BRACKETS\s*;/g;
	$d{staticnew}=$b=~/::staticnew\s*;/;
	$d{staticnewout}=$b=~/::staticnewout\s*;/;
	$d{staticoccupy}=$b=~/::staticoccupy\s*;/;
	$d{staticpush}=$b=~/::staticpush\s*;/;
	$d{staticpop}=$b=~/::staticpop\s*;/;
	$d{staticfree}=$b=~/::staticfree\s*;/;
	$d{allstatic}=$b=~/::allstatic\s*;/;
	$d{externnew}=$b=~/::externnew\s*;/;
	$d{externnewout}=$b=~/::externnewout\s*;/;
	$d{externoccupy}=$b=~/::externoccupy\s*;/;
	$d{externpush}=$b=~/::externpush\s*;/;
	$d{externpop}=$b=~/::externpop\s*;/;
	$d{externfree}=$b=~/::externfree\s*;/;
	$d{allextern}=$b=~/::allextern\s*;/;
	$d{index_type}=($b=~/::index_type\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{length}=($b=~/::length\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{queue}=($b=~/::queue\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	@{$d{array}}=$b=~/::array\s*\{\s*$REGEXP_NESTED_BRACKETS\s*$REGEXP_NESTED_BRACKETS\s*\}\s*;/;
	return %d;
}

sub loestack_compose_declarations($$){
	my ($prefix,$d)=(@_);
	my %c=();
	$c{declnew}=($d->{staticnew}||$d->{allstatic}?'static ':'')."struct $prefix*$prefix\_new($d->{index_type} start_queue_length)";
	$c{declnewout}=($d->{staticnewout}||$d->{allstatic}?'static ':'')."int $prefix\_newout(struct $prefix**out,$d->{index_type} start_queue_length)";
	$c{decloccupy}=($d->{staticoccupy}||$d->{allstatic}?'static ':'').
		"enum $prefix\_occupy_result $prefix\_occupy(struct $prefix**ps".
		(defined $d->{queue}?'':",$d->{index_type}*pque").
		(defined $d->{length}?'':",$d->{index_type}*plen").
		",$d->{index_type} amount)";
	$c{declpush}=($d->{staticpush}||$d->{allstatic}?'static ':'').
		"enum $prefix\_occupy_result $prefix\_push(struct $prefix**ps".
		(defined $d->{queue}?'':",$d->{index_type}*pque").
		(defined $d->{length}?'':",$d->{index_type}*plen").
		",const ${$d->{array}}[0] item)";
	$c{declpop}=($d->{staticpop}||$d->{allstatic}?'static ':'').
		"${$d->{array}}[0] $prefix\_pop(struct $prefix*s".
		(defined $d->{length}?'':",$d->{index_type}*plen").")";
	$c{declfree}=($d->{staticfree}||$d->{allstatic}?'static ':'').
		"void $prefix\_free(struct $prefix*s)";
	return %c;
}

sub loestack_compose_definitions($$$){
	my ($prefix,$t,$d)=(@_);
	my %f=();
	$f{defnew}=qq#$d->{declnew}\{
	struct $prefix*s;
	size_t rsz;
	if(__builtin_mul_overflow(sizeof(${$t->{array}}[0]),start_queue_length,&rsz) ||
		__builtin_add_overflow(sizeof(struct $prefix),rsz,&rsz)){
		LOE_STACK_LOG_OVERFLOW_ERROR;
		return NULL;
	}
	s=LOE_STACK_MALLOC(rsz);
	if(!s){
		LOE_STACK_LOG_CRITICAL_MALLOC_ERROR;
	}#.(defined $t->{queue}||defined $t->{length}?qq#else{
		#.(defined $t->{queue}?"s->$t->{queue}=start_queue_length;\n":'').
		(defined $t->{length}?"s->$t->{length}=0;\n":'')."\t}\n":'').qq#
	return s;
}
#;
	my $len=defined $t->{length}?"s->$t->{length}=0;\n":'';
	my $que=defined $t->{queue}?"s->$t->{queue}=start_queue_length;\n":'';
	$f{defnewout}=qq#$d->{declnewout}\{
	struct $prefix*s;
	size_t rsz;
	if(__builtin_mul_overflow(sizeof(${$t->{array}}[0]),start_queue_length,&rsz) ||
		__builtin_add_overflow(sizeof(struct $prefix),rsz,&rsz)){
		LOE_STACK_LOG_OVERFLOW_ERROR;
		return !!0;
	}
	s=LOE_STACK_MALLOC(rsz);
	if(!s){
		LOE_STACK_LOG_CRITICAL_MALLOC_ERROR;
	}else{
		$len$que*out=s;
	}
	return !!s;
}
#;
	$len=defined $t->{length}?"ps[0]->$t->{length}":'*plen';
	$que=defined $t->{queue}?"ps[0]->$t->{queue}":'*pque';
	my $nsque=defined $t->{queue}?"ns->$t->{queue}":'*pque';
	$f{defoccupy}=qq#$d->{decloccupy}\{
	$t->{index_type} nl;
	if(__builtin_add_overflow($len,amount,&nl)){
		LOE_STACK_LOG_OVERFLOW_ERROR;
		return $prefix\_occupy_overflow_error;
	}
	enum $prefix\_occupy_result e;
	if(nl>$que){
		$t->{index_type} nm= $que;
		do{
			if(__builtin_mul_overflow(nm,2,&nm)){
				nm= -1<0?((typeof(nm))1<<(sizeof(nm)*8-2))-1+((typeof(nm))1<<(sizeof(nm)*8-2)):-1;
				break;
			}
		}while(nl>nm);
		size_t rsz;
		if(__builtin_mul_overflow(nm,sizeof(${$t->{array}}[0]),&rsz) ||
			__builtin_add_overflow(rsz,sizeof(struct $prefix),&rsz)){
			LOE_STACK_LOG_OVERFLOW_ERROR;
			return $prefix\_occupy_overflow_error;
		}
		struct $prefix*ns=LOE_STACK_REALLOC(ps[0],rsz);
		if(!ns){
			LOE_STACK_LOG_CRITICAL_REALLOC_ERROR;
			return $prefix\_occupy_critical_realloc_error;
		}
		$nsque=nm;
		e=ps[0]!=ns?$prefix\_occupy_ok_new_pointer:$prefix\_occupy_ok;
		ps[0]=ns;
	}else{
		e=$prefix\_occupy_ok;
	}
	$len=nl;
	return e;
}
#;
	$f{defpush}=qq#$d->{declpush}\{
	enum $prefix\_occupy_result e=$prefix\_occupy(ps#.
		(defined $t->{queue}?'':',pque').
		(defined $t->{length}?'':',plen').qq#,1);
	if(e==$prefix\_occupy_ok || e==$prefix\_occupy_ok_new_pointer)
		ps[0]->${$t->{array}}[1]\[$len-1\]=item;
	return e;
}
#;
	$len=defined $t->{length}?"s->$t->{length}":'*plen';
	$f{defpop}=qq#$d->{declpop}\{
	LOE_STACK_ASSERT($len>0);
	return s->${$t->{array}}[1]\[--$len\];
}
#;
	$f{deffree}=qq#$d->{declfree}\{
	LOE_STACK_FREE(s);
}
#;
	return %f;
}

sub loestack_compose_nonstatic($$){
	my($t,$d)=(@_);
	return ($t->{staticnew}||$t->{allstatic}?'':($t->{externnew} || $t->{allextern}?'extern ':'')."$d->{declnew};\n").
			($t->{staticnewout}||$t->{allstatic}?'':($t->{externnewout} || $t->{allextern}?'extern ':'')."$d->{declnewout};\n").
			($t->{staticoccupy}||$t->{allstatic}?'':($t->{externoccupy} || $t->{allextern}?'extern ':'')."$d->{decloccupy};\n").
			($t->{staticpush}||$t->{allstatic}?'':($t->{externpush} || $t->{allextern}?'extern ':'')."$d->{declpush};\n").
			($t->{staticpop}||$t->{allstatic}?'':($t->{externpop} || $t->{allextern}?'extern ':'')."$d->{declpop};\n").
			($t->{staticfree}||$t->{allstatic}?'':($t->{externfree} || $t->{allextern}?'extern ':'')."$d->{declfree};\n");
}

sub loestack($){
	sub _loestack($$){
		my($prefix,$body)=(@_);
		my %t=loestack_get_tokens($body);
		my %d=loestack_compose_declarations($prefix,\%t);
		my $nonstatic=loestack_compose_nonstatic(\%t,\%d);
		_loestore($_,$nonstatic) for(@{$t{storenonstatic}});
		my $enum=qq#enum $prefix\_occupy_result{
	$prefix\_occupy_ok,$prefix\_occupy_ok_new_pointer,$prefix\_occupy_overflow_error,$prefix\_occupy_critical_realloc_error
	};
	#;
		_loestore($_,$enum) for(@{$t{storeenum}});
		my $struct="struct $prefix\{\n".
			($body=~s/::$REGEXP_C_ID\s*(?:$REGEXP_NESTED_BRACKETS)?\s*;//rg).
			"}$t{afterstruct};";
		_loestore($_,$struct) for(@{$t{storestruct}});
		my %f=loestack_compose_definitions($prefix,\%t,\%d);
		return ($t{hideenum}?'':$enum).
			($t{hidestruct}?'':$struct).$f{defnew}.$f{defnewout}.$f{defoccupy}.
			$f{defpush}.$f{defpop}.$f{deffree};
	}
	return shift=~s/(^|\W)loe::stack\s*\(\s*($REGEXP_C_ID)\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._loestack($2,$3)/erg;
}

sub loelist_get_tokens($){
	my $b=shift;
	my %d=();
	$d{staticlistnew}=$b=~/::staticlistnew\s*;/;
	$d{staticlistnewout}=$b=~/::staticlistnewout\s*;/;
	$d{staticappend}=$b=~/::staticappend\s*;/;
	$d{staticremove}=$b=~/::staticremove\s*;/;
	$d{staticswap}=$b=~/::staticswap\s*;/;
	$d{externlistnew}=$b=~/::externlistnew\s*;/;
	$d{externlistnewout}=$b=~/::externlistnew\s*;/;
	$d{externappend}=$b=~/::externappend\s*;/;
	$d{externremove}=$b=~/::externremove\s*;/;
	$d{externswap}=$b=~/::externswap\s*;/;
	$d{first}=($b=~/::first\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{last}=($b=~/::last\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{efirst}=($b=~/::efirst\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{elast}=($b=~/::elast\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{prev}=($b=~/::prev\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{next}=($b=~/::next\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{eprev}=($b=~/::eprev\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	$d{enext}=($b=~/::enext\s*$REGEXP_NESTED_BRACKETS\s*;/)[0];
	@{$d{item}}=$b=~/::item\s*\{\s*$REGEXP_NESTED_BRACKETS\s*$REGEXP_NESTED_BRACKETS\s*\}\s*;/;
	return %d;
}

sub loelist_compose_declarations($$){
	my ($prefix,$t)=(@_);
	my %c=();
	$c{decllistnew}=($t->{staticlistnew}||$t->{allstatic}?'static ':'').
		"struct $prefix*$prefix\_list_new($t->{index_type} start_queue_length)";
	$c{decllistnewout}=($t->{staticlistnewout}||$t->{allstatic}?'static ':'').
		"int $prefix\_list_newout(struct $prefix**out,$t->{index_type} start_queue_length)";
	my $que=defined $t->{queue}?'':",$t->{index_type} *pque";
	my $que_remove=defined $t->{queue}?'':",const $t->{index_type} pque";
	my $len=defined $t->{length}?'':",$t->{index_type} *plen";
	$c{declappend}=($t->{staticappend}||$t->{allstatic}?'static ':'').
		"enum $prefix\_occupy_result $prefix\_append(struct $prefix**ps$que$len,const ${$t->{item}}[0] item)";
	$c{declremove}=($t->{staticremove}||$t->{allstatic}?'static ':'').
		"void $prefix\_remove(struct $prefix*s$que_remove$len,$t->{index_type} index)";
	$c{declswap}=($t->{staticswap}||$t->{allstatic}?'static ':'').
		"void $prefix\_swap(struct $prefix*s,$t->{index_type} a,$t->{index_type} b)";
	return %c;
}

sub loelist_compose_nonstatic($$){
	my($t,$d)=(@_);
	return ($t->{staticlistnew}||$t->{allstatic}?'':($t->{externlistnew}||$t->{allextern}?'extern ':'')."$d->{decllistnew};\n").
			($t->{staticlistnewout}||$t->{allstatic}?'':($t->{externlistnewout}||$t->{allextern}?'extern ':'')."$d->{decllistnewout};\n").
			($t->{staticappend}||$t->{allstatic}?'':($t->{externappend}||$t->{allextern}?'extern ':'')."$d->{declappend};\n").
			($t->{staticremove}||$t->{allstatic}?'':($t->{externremove}||$t->{allextern}?'extern ':'')."$d->{declremove};\n").
			($t->{staticswap}||$t->{allstatic}?'':($t->{externswap}||$t->{allextern}?'extern ':'')."$d->{declswap};\n");
}

sub loelist_compose_definitions($$$){
	my($prefix,$t,$d)=(@_);
	my %f=();
	my $saveque=defined $t->{queue}?"\ns->$t->{queue}=start_queue_length;\n":'';
	my $savelen=defined $t->{length}?"\ns->$t->{length}=0;\n":'';
	$f{deflistnew}=qq#$d->{decllistnew}\{
	LOE_STACK_ASSERT(start_queue_length>1);
	struct $prefix*s=$prefix\_new(start_queue_length);
	if(s){
		s->$t->{first}=s->$t->{last}=s->$t->{elast}=0;$saveque
		s->$t->{efirst}=start_queue_length-1;
		for($t->{index_type} i=0;i<start_queue_length-1;++i){
			s->${$t->{array}}[1]\[i\].$t->{eprev}=i+1;
			s->${$t->{array}}[1]\[i+1\].$t->{enext}=i;
		}$savelen
	}
	return s;
}#;
	$f{deflistnewout}=qq#$d->{decllistnewout}\{
	LOE_STACK_ASSERT(start_queue_length>1);
	struct $prefix*s=$prefix\_new(start_queue_length);
	if(s){
		s->$t->{first}=s->$t->{last}=s->$t->{elast}=0;$saveque
		s->$t->{efirst}=start_queue_length-1;
		for($t->{index_type} i=0;i<start_queue_length-1;++i){
			s->${$t->{array}}[1]\[i\].$t->{eprev}=i+1;
			s->${$t->{array}}[1]\[i+1\].$t->{enext}=i;
		}$savelen
		*out=s;
	}
	return !!s;
}#;
	my $que=defined $t->{queue}?"ps[0]->$t->{queue}":'*pque';
	my $len=defined $t->{length}?"ps[0]->$t->{length}":'*plen';
	my $nsque=defined $t->{queue}?"ns->$t->{queue}":'*pque';
	my $nslen=defined $t->{length}?"ns->$t->{length}":'*plen';
	$f{defappend}=qq#$d->{declappend}\{
	$t->{index_type} nl;
	if(__builtin_add_overflow($len,1,&nl)){
		LOE_STACK_LOG_OVERFLOW_ERROR;
		return $prefix\_occupy_overflow_error;
	}
	enum $prefix\_occupy_result e;
	if(nl>$que){
		$t->{index_type} nm= $que;
		do{
			if(__builtin_mul_overflow(nm,2,&nm)){
				nm= -1<0?((typeof(nm))1<<(sizeof(nm)*8-2))-1+((typeof(nm))1<<(sizeof(nm)*8-2)):-1;
				break;
			}
		}while(nl>nm);
		size_t rsz;
		if(__builtin_mul_overflow(nm,sizeof(${$t->{array}}[0]),&rsz) ||
			__builtin_add_overflow(rsz,sizeof(struct $prefix),&rsz)){
			LOE_STACK_LOG_OVERFLOW_ERROR;
			return $prefix\_occupy_overflow_error;
		}
		struct $prefix*ns=LOE_STACK_REALLOC(ps[0],rsz);
		if(!ns){
			LOE_STACK_LOG_CRITICAL_REALLOC_ERROR;
			return $prefix\_occupy_critical_realloc_error;
		}
		ns->$t->{elast}= $nsque;
		ns->$t->{efirst}=nm-1;
		for($t->{index_type} i= $nsque;i<nm-1;++i){
			ns->${$t->{array}}[1]\[i\].$t->{eprev}=i+1;
			ns->${$t->{array}}[1]\[i+1\].$t->{enext}=i;
		}
		$nsque=nm;
		e=ps[0]!=ns?$prefix\_occupy_ok_new_pointer:$prefix\_occupy_ok;
		ps[0]=ns;
	}else{
		e=$prefix\_occupy_ok;
	}
	ps[0]->${$t->{array}}[1]\[ps[0]->$t->{last}\].$t->{next}=ps[0]->$t->{elast};
	ps[0]->${$t->{array}}[1]\[ps[0]->$t->{elast}\].$t->{prev}=ps[0]->$t->{last};
	ps[0]->$t->{last}=ps[0]->$t->{elast};
	if(($len=nl)!=$que)
		ps[0]->$t->{elast}=ps[0]->${$t->{array}}[1]\[ps[0]->$t->{elast}\].$t->{eprev};
	ps[0]->${$t->{array}}[1]\[ps[0]->$t->{last}\].${$t->{item}}[1]=item;
	return e;
}
#;
	my $slen=defined $t->{length}?"s->$t->{length}":'*plen';
	#~ my $sque=defined $t->{queue}?"s->$t->{queue}":'*pque';
	my $sque=defined $t->{queue}?"s->$t->{queue}":'pque';
	$f{defremove}=qq#$d->{declremove}\{
	LOE_STACK_ASSERT($slen>0);
	if($slen>1){
		if(index!=s->$t->{first} && index!=s->$t->{last}){
			s->${$t->{array}}[1]\[s->${$t->{array}}[1]\[index].$t->{prev}\].$t->{next}=
				s->${$t->{array}}[1]\[index\].$t->{next};
			s->${$t->{array}}[1]\[s->${$t->{array}}[1]\[index].$t->{next}\].$t->{prev}=
				s->${$t->{array}}[1]\[index\].$t->{prev};
		}else if(index==s->$t->{last}){
			s->$t->{last}=s->${$t->{array}}[1]\[index\].$t->{prev};
		}else if(index==s->$t->{first}){
			s->$t->{first}=s->${$t->{array}}[1]\[index\].$t->{next};
		}
	}
	if($slen!=$sque){
		s->${$t->{array}}[1]\[s->$t->{elast}\].$t->{enext}=index;
		s->${$t->{array}}[1]\[index\].$t->{eprev}=s->$t->{elast};
	}else{
		s->$t->{efirst}=index;
	}
	s->$t->{elast}=index;
	--($slen);
}
#;
	$f{defswap}=qq#$d->{declswap}\{
	LOE_STACK_ASSERT($slen>1);
	${$t->{item}}[0] t=s->${$t->{array}}[1]\[a].${$t->{item}}[1];
	s->${$t->{array}}[1]\[a].${$t->{item}}[1]=s->${$t->{array}}[1]\[b].${$t->{item}}[1];
	s->${$t->{array}}[1]\[b].${$t->{item}}[1]=t;
}
#;
	return %f;
}

sub loelist($){
	sub _loelist($$){
		my ($prefix,$body)=(@_);
		my %t=(loestack_get_tokens($body),loelist_get_tokens($body));
		my %d=(loestack_compose_declarations($prefix,\%t),
			loelist_compose_declarations($prefix,\%t));
		my $nonstatic=loestack_compose_nonstatic(\%t,\%d).
			loelist_compose_nonstatic(\%t,\%d);
		_loestore($_,$nonstatic) for(@{$t{storenonstatic}});
		my %f=(loestack_compose_definitions($prefix,\%t,\%d),
			loelist_compose_definitions($prefix,\%t,\%d));
		my $enum=qq#enum $prefix\_occupy_result{
	$prefix\_occupy_ok,$prefix\_occupy_ok_new_pointer,$prefix\_occupy_overflow_error,$prefix\_occupy_critical_realloc_error
};
#;
		_loestore($_,$enum) for(@{$t{storeenum}});
		my $struct="struct $prefix\{\n".
			($body=~s/::$REGEXP_C_ID\s*(?:$REGEXP_NESTED_BRACKETS)?\s*;//rg).
			"}$t{afterstruct};";
		_loestore($_,$struct) for(@{$t{storestruct}});
		return ($t{hideenum}?'':$enum).
				($t{hidestruct}?'':$struct).$f{defnew}.$f{defnewout}.$f{defoccupy}.
				$f{defpush}.$f{defpop}.$f{deffree}.$f{deflistnew}.$f{deflistnewout}.$f{defappend}.$f{defremove}.$f{defswap};
	}
	return shift=~s/(^|\W)loe::list\s*\(\s*($REGEXP_C_ID)\s*\)\s*$REGEXP_NESTED_BRACKETS/$1._loelist($2,$3)/erg;
}

sub loereplace{
	my $body=shift;
	my @records=();
	$body=$body=~s/(^|\W)loe::replace\s*\(\s*$REGEXP_NESTED_BRACKETS\s*,\s*$REGEXP_NESTED_BRACKETS\s*\)\s*;\s*/push @records,[$2,$3];""/ergm;
	for my $r (@records){
		$body=$body=~s/${$r}[0]/${$r}[1]/rg;
	}
	return $body;
}

sub loeeereplace{
	my $body=shift;
	my @records=();
	$body=$body=~s/(^|\W)loe::eereplace\s*\(\s*$REGEXP_NESTED_BRACKETS\s*,\s*$REGEXP_NESTED_BRACKETS\s*\)\s*;\s*/push @records,[$2,$3];""/ergm;
	for my $r (@records){
		$body=$body=~s/${$r}[0]/${$r}[1]/eerg;
	}
	return $body;
}

my @dodo=(
	{
		regexp=>qr/--mutate=([^:]*):([^:]*)/,
		action=>sub{
			my ($srcf,$dstf)=($1,$2);
			overfile($dstf,exomod('indent -sob',loeeereplace(loereplace(loespawn(loestore(loelist(loestack(archiveworks(setarchive(setstack(setlist(iniinfo(iniworks(gperfing(slurpfile($srcf))))))))))))))));
		}
	},
	{
		regexp=>qr/--create-project=([^,]*)((?:,[^:]*:[^,]*)*)/,
		action=>sub{
			my ($project_name,$for_pkg_config)=($1,$2);
			my @pkgconf_libdef=$for_pkg_config=~/,([^:]*)/g;
			my @pkgconf_libpc=$for_pkg_config=~/:([^,]*)/g;
			die if @pkgconf_libdef!=@pkgconf_libpc;
			mkdir $project_name or die;
			mkdir $project_name.'/src' or die;
			overexe("$project_name/src/$current_script_base",slurpfile($current_script_path));
			overfile("$project_name/Makefile.am","SUBDIRS=src\n");
			overfile("$project_name/src/main.$current_script_base.c",qq{#include "config.h"

int main(int i,char**v){
	return 0;
}
});
			my ($pkgconf_ac1,$pkgconf_ac2,$pkgconf_am1,$pkgconf_am2)=('','','','');
			if(@pkgconf_libdef){
				chomp(my $pv=`pkg-config --version`);
				die if $?;
				$pkgconf_ac1="\nPKG_PROG_PKG_CONFIG([$pv])\n";
				$pkgconf_ac2="\n";
				$pkgconf_am1="\n$project_name\_CFLAGS=";
				$pkgconf_am2="\n$project_name\_LDADD=";
				for my $i (0..$#pkgconf_libdef){
					chomp($pv=`pkg-config --modversion $pkgconf_libpc[$i]`);
					die if $?;
					$pkgconf_ac2.="PKG_CHECK_MODULES([$pkgconf_libdef[$i]], [$pkgconf_libpc[$i] >= $pv])\n";
					$pkgconf_am1.="\$($pkgconf_libdef[$i]\_CFLAGS) ";
					$pkgconf_am2.="\$($pkgconf_libdef[$i]\_LIBS) ";
				}
			}
			overfile("$project_name/configure.ac",qq{AC_PREREQ([2.69])
AC_CONFIG_AUX_DIR([build-aux])
AC_INIT([$project_name], [1.0])
AC_CONFIG_SRCDIR([src/$current_script_base])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([-Wall -Werror foreign no-dist-gzip dist-xz])

AC_ARG_ENABLE([shadow],
[  --enable-shadow  Turn on the shadow mode],
[case "\${enableval}" in
	yes) shadow=true ;;
	no) shadow=false ;;
	*) AC_MSG_ERROR([bad value \${enableval} for --enable-shadow]) ;;
esac],[shadow=false])
AM_CONDITIONAL([SHADOW], [test x\$shadow = xtrue])

# Checks for programs.
AC_PROG_CC$pkgconf_ac1
AC_CHECK_PROG([GPERF],[gperf],[yes])
AC_CHECK_PROG([INDENT],[indent],[yes])
AC_CHECK_PROG([DARC],[darc],[yes])
test "\$GPERF" != "yes" || test "\$INDENT" != "yes" || test "\$DARC" != "yes" && AC_MSG_ERROR([Some programs are missing])
# Checks for libraries.$pkgconf_ac2

# Checks for header files.

# Checks for typedefs, structures, and compiler characteristics.

# Checks for library functions.

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
});
			overfile("$project_name/src/configure.ac.shadow",qq{AC_PREREQ([2.69])
AC_CONFIG_AUX_DIR([build-aux])
AC_INIT([$project_name], [1.0])
AC_CONFIG_SRCDIR([src/main.c])
AC_CONFIG_HEADERS([config.h])
AM_INIT_AUTOMAKE([-Wall -Werror foreign no-dist-gzip dist-xz])

# Checks for programs.
AC_PROG_CC$pkgconf_ac1

# Checks for libraries.$pkgconf_ac2

# Checks for header files.

# Checks for typedefs, structures, and compiler characteristics.

# Checks for library functions.

AC_CONFIG_FILES([Makefile
                 src/Makefile])
AC_OUTPUT
});
			overfile("$project_name/src/Makefile.am",qq{bin_PROGRAMS=$project_name
CLEANFILES=main.c
BUILT_SOURCES=main.c
main.c:\$(srcdir)/$current_script_base \$(srcdir)/main.$current_script_base.c
	\$(srcdir)/$current_script_base --mutate=\$(srcdir)/main.$current_script_base.c:main.c
$project_name\_SOURCES=main.c$pkgconf_am1$pkgconf_am2
EXTRA_DIST=$current_script_base main.$current_script_base.c configure.ac.shadow Makefile.am.shadow
dist-hook:
if SHADOW
	mv \$(distdir)/Makefile.am.shadow \$(distdir)/Makefile.am
	mv \$(distdir)/configure.ac.shadow \$(top_distdir)/configure.ac
	rm \$(distdir)/$current_script_base \$(distdir)/main.$current_script_base.c
	cd \$(distdir)/..; autoreconf -i
else
	rm \$(distdir)/main.c
endif
});
			overfile("$project_name/src/Makefile.am.shadow",qq{bin_PROGRAMS=$project_name
$project_name\_SOURCES=main.c$pkgconf_am1$pkgconf_am2
});
		}
	}
);

for my $arg (@ARGV){
	for my $doa (@dodo){
		$doa->{action}() if($arg=~/$doa->{regexp}/)
	}
}
