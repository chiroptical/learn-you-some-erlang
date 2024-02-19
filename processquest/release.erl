-module(release).

-export([ build_release/0
			 ]).

build_release() ->
	{ok, Conf} = file:consult("./processquest-1.0.0.config"),
	{ok, Spec} = reltool:get_target_spec(Conf),
	ok = reltool:eval_target_spec(Spec, code:root_dir(), "rel"),
	ok.
