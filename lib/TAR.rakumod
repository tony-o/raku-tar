unit module TAR;

sub tar(*@fs, Str :$prefix = '' --> Buf[uint8]) is export {
  my Buf[uint8] $tar .=new;
  my $pax-header-cnt = 0;
  for @fs -> IO() $f {
    die "{$f.relative} does not exist" unless $f.e;

    #setup
    my $force-pax = try { $prefix ~ $f.relative ~ ($f.d ??'/'!!'')).encode('ascii') } ?? False !! True;
    my $filename = ($prefix ~ $f.relative ~ ($f.d ??'/'!!'')).encode('ascii', :replacement<->);
    my $bytes = ($f.l ?? $f.resolve !! $f.slurp(:bin)) unless $f.d;
    my Buf[uint8] $tarf .=new;
    my Buf[uint8] $paxf .=new;

    #filename
    $tarf.push($filename.elems > 100 ?? ($f.d ?? "{$f.basename}/" !! $f.basename).encode('ascii', :replacement<->).subbuf(0,99) !! $filename.subbuf(0,100));
    $tarf.push(0) while $tarf.elems % 100 != 0; 

    #filemode
    $tarf.push(sprintf("%06o \0", $f.mode).encode('ascii'));

    #ownerid
    $tarf.push(sprintf("%06o \0", $f.user).encode('ascii'));

    #groupid
    $tarf.push(sprintf("%06o \0", $f.group).encode('ascii'));

    #filesize
    $tarf.push(sprintf("%011o ", $bytes.elems).encode('ascii'));

    #mtime
    $tarf.push(sprintf("%011o ", $f.modified).encode('ascii'));

    #checksum
    $tarf.push('        '.encode('ascii'));

    #type flag
    $tarf.push(($f.f ?? '0' !! $f.l ?? '2' !! '5').encode('ascii'));

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
      my $fpath = sprintf("%s path=%s\n", $paxpath.elems + $paxpath.elems.Str.chars + 7, $f.relative).encode('utf8');

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
