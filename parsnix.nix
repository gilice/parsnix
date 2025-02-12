{
  pkgs ? import <nixpkgs> { },
}:
rec {
  utils = rec {
    charAt = str: idx: builtins.substring idx 1 str;
    strlen = builtins.stringLength;
    substringUntilEnd = str: from: builtins.substring from (strlen str - from) str;
    inAsciiRange =
      start: end: c:
      let
        ascii = pkgs.lib.strings.charToInt c;
      in
      ascii >= start && ascii <= end;

    isNumber = c: inAsciiRange 48 57 c;
    isSmallLetter = c: inAsciiRange 97 122 c;
    isCapitalLetter = c: inAsciiRange 65 90 c;
    isLetter = c: isSmallLetter c || isCapitalLetter c;
    isAlphaNumeric = c: isLetter c || isNumber c;

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
    # like lookaheadWhile, but passes the index to the decidefun
    lookaheadWhileCnt =
      decidefun: index: str:
      let
        nextchar = utils.charAt str index;
        decision = if nextchar == "" then false else decidefun nextchar index;
      in
      if !decision then index else lookaheadWhileCnt decidefun (index + 1) str;

    takeWhileInternal =
      min: lookaheadfun: decidefun: str:
      let
        matchLen = lookaheadfun decidefun 0 str;
      in
      if matchLen < min then
        {
          error = "takeWhile: match len ${toString matchLen} < minimum ${toString min}";
          remaining = str;
        }
      else
        {
          results = [ (builtins.substring 0 matchLen str) ];
          remaining = utils.substringUntilEnd str matchLen;
        };
    takeWhile = takeWhileInternal 0 lookaheadWhile;
    takeWhile1 = takeWhileInternal 1 lookaheadWhile;
    # like takeWhile but the decidefun is of format (character: index: true)
    takeWhileCnt = takeWhileInternal 0 lookaheadWhileCnt;
    takeWhileCnt1 = takeWhileInternal 1 lookaheadWhileCnt;

    takeWhileNoneOf = list: str: takeWhile (c: !builtins.elem c list) str;
    takeWhileNoneOf1 = list: str: takeWhile1 (c: !builtins.elem c list) str;
    takeUntil = char: str: takeWhile (c1: c1 != char) str;
    takeUntil1 = char: str: takeWhile1 (c1: c1 != char) str;
    # like takeUntil, but consumes the character itself too as a silent
    takeUntil1C = char: str: seq (takeUntil1 char) (silent (tag char)) str;
    takeN =
      n: str:
      let
        substring = (builtins.substring 0 n str);
      in
      if substring == "" && n != 0 then
        {
          error = "takeN: no more data but n == ${toString n}";
          remaining = str;
        }
      else
        {
          results = [ substring ];
          remaining = utils.substringUntilEnd str n;
        };

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
    altAll = xs: str: pkgs.lib.foldl' (a: b: alt a b) (builtins.head xs) (builtins.tail xs) str;

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
    _countInternal =
      results: n: max: a: str:
      let
        aRes = a str;
      in
      if n == max then
        {
          results = results;
          remaining = str;
        }
      else
        _countInternal (results ++ aRes.results) (n + 1) max a aRes.remaining;
    count =
      n: a: str:
      _countInternal [ ] 0 n str;

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

    alphanumeric = str: takeWhile (c: utils.isAlphaNumeric c) str;
    alphanumeric1 = str: takeWhile1 (c: utils.isAlphaNumeric c) str;
    numeric = str: takeWhile (c: utils.isNumber c) str;
    numeric1 = str: takeWhile1 (c: utils.isNumber c) str;
  };

  demo = with (parsers // utils); {
    url = "https://example.com";
    urlUserPort = "https://someone@example.com:80";
    url3 = "https://someone:password@subdomain.example.com:80/a/b?k1=v1&k2=v2#fragment";
    parseUrl =
      str:
      mergeResults (seqAll [
        (nameSingleResult "scheme" (takeUntil1C ":"))
        # authority
        (silent (tag "//"))
        # userinfo
        (opt (
          nameSingleResult "userinfo" (
            mergeResults (seqAll [
              (nameSingleResult "username" (takeWhileNoneOf [
                "@"
                ":"
              ]))
              (opt (nameSingleResult "password" (seq (silent (tag ":")) (takeUntil "@"))))
              (silent (tag "@"))
            ])
          )
        ))
        (nameSingleResult "host" (takeWhileNoneOf [
          ":"
          "/"
        ]))
        (opt (map1 (x: [ { port = builtins.fromJSON x; } ]) (seq (silent (tag ":")) numeric)))
        (opt (
          nameSingleResult "path" (takeWhileNoneOf [
            "?"
            "#"
          ])
        ))
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
                    (takeWhileNoneOf [
                      "&"
                      "#"
                    ])
                    (opt (silent (tag "&")))
                  ])
                )
              )
            )
          )
        ))

        # fragment
        (opt (nameSingleResult "fragment" (seq (silent (tag "#")) (takeWhile (_: true)))))
      ]) str;
  };
}
