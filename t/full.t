# -*- cperl -*-
use strict;
use warnings;
use utf8;
no warnings 'utf8';

use Test::More tests => 5;
use IPC::Run3;
use IPC::Cmd qw( can_run );
use File::Temp;
use File::Compare;

SKIP: {
  skip "Developer only test", 2 unless can_run('/opt/local/bin/perl');
  my $tmpfile = File::Temp->new();
  my $bbl = $tmpfile->filename;
  my $stdout;

  run3  [ '/opt/local/bin/perl', 'bin/biber', '--nolog', "--outfile=$bbl", 't/tdata/full.bcf' ], \undef, \$stdout, \undef;

  is($? >> 8, 0, 'Full test has zero exit status');
  ok(compare($bbl, 't/tdata/full1.bbl') == 0, 'Testing lossort case and sortinit for macros');
  like($stdout, qr|WARN - Duplicate entry key: 'F1' in file 't/tdata/full\.bib', skipping \.\.\.|ms, 'Testing duplicate/case key warnings - 1');
  like($stdout, qr|WARN - Possible typo \(case mismatch\) between datasource keys: 'f1' and 'F1' in file 't/tdata/full\.bib'|ms, 'Testing duplicate/case key warnings - 2');
  like($stdout, qr|WARN - Possible typo \(case mismatch\) between citation and datasource keys: 'C1' and 'c1' in file 't/tdata/full\.bib'|ms, 'Testing duplicate/case key warnings - 3');
}