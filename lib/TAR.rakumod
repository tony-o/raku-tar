unit module TAR;

sub tar(*@fs, Str :$prefix = '' --> Buf[uint8]) is export {
  my Buf[uint8] $tar .=new;
  my $pax-header-cnt = 0;
  for @fs -> IO() $f {
    die "{$f.relative} does not exist" unless $f.e || $f.l;

    #setup
    my $force-pax = try { ($prefix ~ $f.relative ~ ($f.d ??'/'!!'')).encode('ascii') } ?? False !! True;
    my $filename = ($prefix ~ $f.relative ~ ($f.d ??'/'!!'')).encode('ascii', :replacement<->);
    my $bytes = $f.slurp(:bin) if !$f.d && !$f.l;
    my Buf[uint8] $tarf .=new;
    my Buf[uint8] $paxf .=new;

    #filename
    $tarf.push($filename.elems > 100 ?? ($f.d ?? "{$f.basename}/" !! $f.basename).encode('ascii', :replacement<->).subbuf(0,99) !! $filename.subbuf(0,100));
    $tarf.push(0) while $tarf.elems % 100 != 0; 

    #filemode
    $tarf.push(sprintf("%06o \0", $f.mode//0o600).encode('ascii'));

    #ownerid
    $tarf.push(sprintf("%06o \0", $f.user//1000).encode('ascii'));

    #groupid
    $tarf.push(sprintf("%06o \0", $f.group//1000).encode('ascii'));

    #filesize
    die if $bytes.elems > 0o77777777777;
    $tarf.push(sprintf("%011o ", $f.d ?? 0 !! $bytes.elems).encode('ascii'));

    #mtime
    $tarf.push(sprintf("%011o ", $f.modified//DateTime.now.posix).encode('ascii'));

    #checksum
    $tarf.push('        '.encode('ascii'));

    #type flag
    $tarf.push(($f.l ?? '2' !! $f.f ?? '0' !! '5').encode('ascii'));

    if $f.l {
      $force-pax ||= ( try { $f.resolve.encode('ascii') } ?? False !! $f.resolve.relative.Str.chars > 100 );
      warn "$f is a missing link" if $f.resolve.absolute eq $f.absolute;
      $tarf.push($f.resolve.relative.encode('ascii', :replacement<->).subbuf(0,100))
    }

    $tarf.push(0) while $tarf.elems % 256 != 0;

    #ustar hdr
    $tarf.push("\0ustar\000".encode('ascii'));

    #owner name
    $tarf.push("raku\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0".encode('ascii'));

    #group name
    $tarf.push("raku\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0".encode('ascii'));

    #device major
    $tarf.push("000000 \0".encode('ascii'));

    #device minor
    $tarf.push("000000 \0".encode('ascii'));
    
    $tarf.push(0) while $tarf.elems % 512 != 0;
    
    $tarf.splice: 148, 8, (sprintf("%06o\0 ", ([+] $tarf.subbuf(*-512))).encode('ascii'));

    if $filename.elems > 100 || $force-pax {
      # write meta header
      my $paxnm = "PaxHeader/{$f.basename}".encode('ascii', :replacement<->).subbuf(0,98);
      my $paxpath = $f.relative.encode('utf8');
      my $fpath = sprintf("%s path=%s\n", $paxpath.elems + $paxpath.elems.Str.chars + 8, $f.relative).encode('utf8');

      my $linkpath = $f.resolve.absolute.encode('utf8');
      $fpath ~= sprintf("%s linkpath=%s\n", $linkpath.elems + $linkpath.elems.Str.chars + 12, $f.resolve.absolute).encode('utf8')
        if $f.l;

      $paxf.push($tarf);
      # fix filename
      $paxf.splice: 0, $paxnm.elems, $paxnm;
      $paxf[$_] = 0 for $paxnm.elems..^100;
      # fix file type
      $paxf.splice: 156, 1, 'x'.encode('ascii');

      # fix record size
      $paxf.splice: 124, 12, sprintf("%011o ", $fpath.elems).encode('ascii');

      # prepare checksum
      $paxf.splice: 148, 8, '        '.encode('ascii');
      $paxf.splice: 148, 8, (sprintf("%06o\0 ", ([+] $paxf.subbuf(0,511))).encode('ascii'));

      $paxf.push($fpath);
      $paxf.push(0) while $paxf.elems % 512 != 0;
    }


    $tarf.push($bytes.elems ?? $bytes !! 0) if $bytes;
    $tarf.push(0) while $tarf.elems % 512 != 0;

    $tar.push($paxf);
    $tar.push($tarf);
  }

  $tar.push(0) for 0..^1024;

  $tar;
}
