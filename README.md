# PARSNIX
> from *parse* and *nix*, or alternatively from *parsnip*

## What
A simple implementation of parser combinators in nix. Depends only on `builtins` and a bit of `pkgs.lib`

## Why
Because writing parsers is fun; and writing parser combinators is fun; and because writing a parser combinator in a functional language poses additional, fun challenges.

## How to use
1. **Don't!** This code is written to be read. It copies strings all over the place for a nicer implementation, but that makes it very slow.
    1. Instead, use a derivation and a parser written in another language to parse what you need; IFD if you want the value in pure nix.
    2. If you cannot do that, try a regex.
    3. If you cannot do that, try another parsing library.

2. The structure of the top-level attrset is:

    ```nix
    {
      utils = ...;
      parsers = ...;
      demo = ...;
    }
    ```

    `parsers` contains the basic building blocks on top of which you can implement more fancy combinators.

3. The code is meant to be read in a top-down manner, starting from `tag` and `takeWhile`.
    1. every parser is a function of the type `parser = arg0: arg1: argn: str: definition` where `arg1` through `argn` are zero or more parser-specific arguments of unspecified types, and `str` is the remaining string to parse.
    2. parsers always return an attrset.
    3. a parser which was successful returns an attrset in the following format:
    ```nix
    {
      remaining = ...; # string, a substring of the argument `str`
      results = []; # list of dynamic types.
    }
    ```
    Results are always a list because this makes implementing `seq` nicer. This additionally hinders performance.

    4. a parser which failed returns an attrset in the following format: 
    ```nix
    {
      remaining = ...;
      error = "";
    }
    ```

    The first failure is always returned[^1]; there is no error trace kept.

[^1]: except if you explicitly ignore it via some parser like `opt` or `alt`

## Demo
The project includes a demo for a (non complete and non standards-compliant), basic URL parser.
You can run it like:
```console
$ nix repl -f 'parsnix.nix'
nix-repl> :p demo.url3
https://someone:password@subdomain.example.com:80/a/b?k1=v1&k2=v2

nix-repl> :p demo.parseUrl demo.url3
{
  remaining = "";
  results = [
    {
      params = {
        k1 = "v1";
        k2 = "v2";
      };
      password = "password";
      path = "/a/b";
      port = 80;
      protocol = "https";
      segments = [
        "subdomain"
        "example"
        "com"
      ];
      user = "someone";
    }
  ];
}
```
