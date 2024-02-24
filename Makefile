format:
	rebar3 fmt -w

shell:
	rebar3 shell

diagrams:
	bash diagrams/build-diagrams.sh

lint:
	rebar3 dialyzer

test:
	rebar3 eunit

.PHONY: format shell diagrams lint test
