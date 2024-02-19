#!/usr/bin/env bash

for dir in ./apps/{regis,sockserv,processquest}-1.{0,1}.0; do
	pushd $dir
	erl -make
	popd
done
