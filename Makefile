ifeq ($(shell which ikiwiki),)
IKIWIKI=echo "** ikiwiki not found" >&2 ; echo ikiwiki
else
IKIWIKI=ikiwiki
endif

SRC=$(shell pwd)
DST=html
DEPLOY_TO=aither@rhea.havefun.cz:/home/aither/public_html/vpsadmin-doc/
COMMAND=${IKIWIKI} -v --wikiname vpsAdmin --plugin=goodstuff --plugin=theme \
	--set theme=actiontabs --exclude=${DST} --exclude=Makefile --rcs git ${SRC} ${DST}

.PHONY: build
.PHONY: mkdir
.PHONY: refresh
.PHONY: clean
.PHONY: deploy

build: mkdir
	${COMMAND} --rebuild

mkdir:
	mkdir -p ${DST}

refresh: mkdir
	${COMMAND} --refresh

clean:
	rm -rf .ikiwiki ${DST}

deploy: refresh
	rsync -av ${DST}/ ${DEPLOY_TO}
