#include <stdio.h>

int main(int i,char**v){
	if(i>1){
		FILE *f=fopen(v[1],"rb");
		if(!f){
			perror(NULL);
		}else{
			if(fseek(f,0,SEEK_END)){
				perror(NULL);
			}else{
				long fp=ftell(f);
				if(fp==-1){
					perror(NULL);
				}else{
					printf("<%lu>\n",fp);
				}
			}
			fclose(f);
		}
		return 0;
	}
	return 1;
}
