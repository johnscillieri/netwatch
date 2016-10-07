SOURCES = \
	src/eternity.nim \
	src/host.nim \
	src/inifiles.nim \
	src/linux.nim \
	src/netutils.nim \
	src/netwatch.nim \
	src/oui.nim \
	src/ui.nim

BIN_NAME = netwatch
RELEASE_BIN = $(addsuffix _release,$(BIN_NAME))
DEBUG_BIN = $(addsuffix _debug,$(BIN_NAME))

DOCKERFILE = Dockerfile
DOCKER_IMAGE_NAME = nim_build
DOCKER_RUN = docker run -v `pwd`:/src --rm $(DOCKER_IMAGE_NAME)
DOCKER_SET_OWNERSHIP = $(DOCKER_RUN) chown `id -u $(USER)`:`id -u $(USER)`

UPX := $(shell command -v upx 2> /dev/null)

SHARED_FLAGS = \
	--cc: clang \
    --passL: "-static" \
    --define: usePcreHeader \
    --passL: "-lpcre" \
    --passL: "-lpthread" \
    --define: nimOldSplit

RELEASE_FLAGS = \
	--define: release \
	--nimcache: nimcache_release \
	--deadCodeElim: on \
	--lineTrace: off \
	--stackTrace: off \
	--checks: off

DEBUG_FLAGS = \
	--define: debug \
	--nimcache: nimcache_debug \
	--deadCodeElim: on \
	--debuginfo \
	--debugger: native \
	--linedir: on \
	--stacktrace: on \
	--linetrace: on \
	--verbosity: 1

all: docker release debug package

release: ./bin/$(RELEASE_BIN)

debug: ./bin/$(DEBUG_BIN)

package: ./bin/$(BIN_NAME)

docker: $(DOCKERFILE)
	docker build -t $(DOCKER_IMAGE_NAME) . && \
	touch $@ # create an empty target file so it doesn't keep rebuilding

./bin/$(RELEASE_BIN): $(SOURCES) docker
	cd src && \
	$(DOCKER_RUN) nim $(SHARED_FLAGS) $(RELEASE_FLAGS) --out:$(RELEASE_BIN) c netwatch && \
	$(DOCKER_SET_OWNERSHIP) $(RELEASE_BIN) && \
	mkdir -p ../bin && \
	mv $(RELEASE_BIN) ../bin

./bin/$(DEBUG_BIN): $(SOURCES) docker
	cd src && \
	$(DOCKER_RUN) nim $(SHARED_FLAGS) $(DEBUG_FLAGS) --out:$(DEBUG_BIN) c netwatch && \
	$(DOCKER_SET_OWNERSHIP) $(DEBUG_BIN) && \
	mkdir -p ../bin && \
	mv $(DEBUG_BIN) ../bin && \
	rm -rf $(DEBUG_BIN).ndb

./bin/$(BIN_NAME): ./bin/$(RELEASE_BIN)
	cp ./bin/$(RELEASE_BIN) ./bin/$(BIN_NAME)
	strip -s ./bin/$(BIN_NAME)
ifdef UPX
	upx --ultra-brute ./bin/$(BIN_NAME)
else
	@echo "\nUPX not found so binary isn't packed, only stripped.\n"
endif
	ls -lh ./bin

./src/ui: src/ui.nim docker
	cd src && \
	$(DOCKER_RUN) nim c ui.nim && \
	$(DOCKER_SET_OWNERSHIP) ui

./src/oui.nim: docker
	$(DOCKER_RUN) wget http://linuxnet.ca/ieee/oui/nmap-mac-prefixes -O src/oui.nim && \
	sed -i 's/\(.*\)/"\1",/g' src/oui.nim && \
	sed -i 's/\t/":"/g' src/oui.nim && \
	sed -i '1s/^/let oui_table* = {/' src/oui.nim && \
	sed -i '1s/^/import tables\n/' src/oui.nim && \
	echo "}.toTable()" >> src/oui.nim

clean:
	rm -rf ./bin/*
	$(DOCKER_RUN) rm -rf src/nimcache_release
	$(DOCKER_RUN) rm -rf src/nimcache_debug

cleanall: clean
	rm -rf docker
	rm -rf src/oui.nim
