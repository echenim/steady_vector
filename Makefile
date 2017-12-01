REBAR3_URL=https://s3.amazonaws.com/rebar3/rebar3

ifeq ($(wildcard rebar3),rebar3)
	REBAR3 = $(CURDIR)/rebar3
endif

REBAR3 ?= $(shell test -e `which rebar3` 2>/dev/null && which rebar3 || echo "./rebar3")

ifeq ($(REBAR3),)
	REBAR3 = $(CURDIR)/rebar3
endif

TEST_PROFILE ?= test

.PHONY: all build clean check dialyzer xref test cover

all: build

build: $(REBAR3)
	@$(REBAR3) compile

$(REBAR3):
	wget $(REBAR3_URL) || curl -Lo rebar3 $(REBAR3_URL)
	@chmod a+x rebar3

clean:
	@$(REBAR3) clean

check: dialyzer xref

dialyzer:
	@$(REBAR3) as development dialyzer

xref:
	@$(REBAR3) as development xref

test:
	@$(REBAR3) as $(TEST_PROFILE) eunit

cover: test
	@$(REBAR3) as $(TEST_PROFILE) cover

benchmark_quick:
	make -C steady_vector_bench/ quick

benchmark_full:
	make -C steady_vector_bench/ full
