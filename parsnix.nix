{
  pkgs ? import <nixpkgs> { },
}:
rec {
  utils = rec {
    charAt = str: idx: builtins.substring idx 1 str;
    strlen = builtins.stringLength;
    substringUntilEnd = str: from: builtins.substring from (strlen str - from) str;
    isNumber =
      c:
      builtins.elem c [
        "1"
        "2"
        "3"
        "4"
        "5"
        "6"
        "7"
        "8"
        "9"
        "0"
      ];

    mapIfOk = parsed: fun: if parsed ? results then (fun parsed) else parsed;
    nameSingleResult =
      name: a: str:
      (parsers.map1 (x: [ { ${name} = x; } ]) a) str;
  };

  parsers = rec {
    tag =
      mtag: str:
      let
        taglen = builtins.stringLength mtag;
      in
      if builtins.substring 0 taglen str == mtag then
        {
          results = [ mtag ];
          remaining = utils.substringUntilEnd str taglen;
        }
      else
        {
          error = "tag `${mtag}`";
          remaining = str;
        };

    # used for implementing takeWhile
    lookaheadWhile =
      decidefun: index: str:
      let
        nextchar = utils.charAt str index;
        decision = if nextchar == "" then false else decidefun nextchar;
      in
      if !decision then index else lookaheadWhile decidefun (index + 1) str;

    takeWhileMin =
      min: decidefun: str:
      let
        matchLen = lookaheadWhile decidefun 0 str;
      in
      if matchLen < min then
        {
          error = "takeWhile: match len ${matchLen} < minimum ${min}";
          remaining = str;
        }
      else
        {
          results = [ (builtins.substring 0 matchLen str) ];
          remaining = utils.substringUntilEnd str matchLen;
        };
    takeWhile = takeWhileMin 0;
    takeWhile1 = takeWhileMin 1;
    takeWhileNoneOf = list: str: takeWhile (c: !builtins.elem c list) str;
    takeWhileNoneOf1 = list: str: takeWhile1 (c: !builtins.elem c list) str;
    takeUntil = char: str: takeWhile (c1: c1 != char) str;
    takeUntil1 = char: str: takeWhile1 (c1: c1 != char) str;

    seq =
      a: b: str:
      utils.mapIfOk (a str) (
        aRes:
        utils.mapIfOk (b aRes.remaining) (bRes: {
          results = aRes.results ++ bRes.results;
          remaining = bRes.remaining;
        })
      );
    seqAll = xs: str: pkgs.lib.foldl (a: b: seq a b) (builtins.head xs) (builtins.tail xs) str;

    alt =
      a: b: str:
      let
        aRes = a str;
      in
      if aRes ? results then aRes else (b str);
    altAll = xs: str: pkgs.lib.foldl (a: b: alt a b) (builtins.head xs) (builtins.tail xs) str;

    _manyInternal =
      results: a: str:
      let
        aRes = a str;
      in
      if aRes ? results then
        _manyInternal (results ++ aRes.results) a aRes.remaining
      else
        {
          results = results;
          remaining = str;
        };
    many = a: str: _manyInternal [ ] a str;

    when =
      a: goodfn: errfn: str:
      let
        aRes = a str;
      in
      if aRes ? results then (goodfn aRes) else (errfn aRes);
    map =
      mapfn: a: str:
      utils.mapIfOk (a str) (aRes: {
        remaining = aRes.remaining;
        results = mapfn aRes.results;
      });

    map1 =
      mapfn: a: str:
      map (x: mapfn (builtins.head x)) a str;
    # in some contexts builtins.map would override parsers.map; so use this instead
    pmap = map;
    pmap1 = map1;
    opt =
      a: str:
      when a (x: x) (x: {
        results = [ ];
        remaining = str;
      }) str;

    silent = a: str: (map (x: [ ]) a) str;
    mergeResults =
      a: str:
      utils.mapIfOk (a str) (aRes: {
        results = [ (pkgs.lib.foldl pkgs.lib.recursiveUpdate { } aRes.results) ];
        remaining = aRes.remaining;
      });
    separated1 =
      a: separator: str:
      seq a (many (seq separator a)) str;
  };

  demo = with parsers; {
    url = "https://example.com";
    urlUserPort = "https://someone@example.com:80";
    url3 = "https://someone:password@subdomain.example.com:80/a/b?k1=v1&k2=v2";
    parseUrl =
      str:
      mergeResults (seqAll [
        (nameSingleResult "protocol" (alt (tag "https") (tag "http")))
        (silent (tag "://"))
        #user
        (opt (
          nameSingleResult "user" (
            seq (takeWhileNoneOf [
              "@"
              ":"
            ]) (silent (alt (tag "@") (tag ":")))
          )
        ))
        (opt (
          nameSingleResult "password" (
            seq (takeWhileNoneOf [
              "@"
              ":"
              "."
            ]) (silent (tag "@"))
          )
        ))
        (pmap (x: [ { segments = x; } ]) (
          separated1 (takeWhileNoneOf [
            "."
            ":"
            "/"
          ]) (silent (tag "."))
        ))
        (opt (
          map1 (x: [ { port = pkgs.lib.toIntBase10 x; } ]) (
            seq (silent (tag ":")) (takeWhile (c: utils.isNumber c))
          )
        ))
        (opt (nameSingleResult "path" (takeUntil "?")))
        # query params
        (opt (
          nameSingleResult "params" (
            seq (silent (tag "?")) (
              mergeResults (
                many (
                  pmap (x: [ { ${builtins.elemAt x 0} = builtins.elemAt x 1; } ]) (seqAll [
                    # key
                    (takeUntil "=")
                    (silent (tag "="))
                    # value
                    (takeUntil "&")
                    (opt (silent (tag "&")))
                  ])
                )
              )
            )
          )
        ))
      ]) str;
  };
}
