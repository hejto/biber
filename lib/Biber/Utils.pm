package Biber::Utils;
use strict;
use warnings;
use Carp;
use File::Find;
use IPC::Cmd qw( can_run run );
use LaTeX::Decode;
use Biber::Constants;
use Regexp::Common qw( balanced );
use re 'eval';
use base 'Exporter';
use Log::Log4perl qw(:no_extra_logdie_message);

my $logger = Log::Log4perl::get_logger('main');

=encoding utf-8

=head1 NAME

Biber::Utils - Various utility subs used in Biber

=cut

=head1 VERSION

Version 0.4

=head1 SYNOPSIS

=head1 EXPORT

All functions are exported by default.

=cut

our @EXPORT = qw{ bibfind parsename terseinitials makenameid makenameinitid
  normalize_string normalize_string_underscore latexescape array_minus
  remove_outer getinitials tersify ucinit };

######
# These are used in the functions parsename and getinitials :
#
# TODO move to Biber::Constants ?
#
# Semitic (or eventually other) last names could begin with NONSORTDIACRITICS like ʿ or ‘ (e.g. ʿAlī)
my $NONSORTDIACRITICS = qr/[\x{2bf}\x{2018}]/; # more?

# Semitic (or eventually other) names may be prefixed with an article (e.g. al-Hasan, as-Saleh)
my $NONSORTPREFIX = qr/\p{Ll}{2}-/; # etc

#
######

=head1 FUNCTIONS

=head2 bibfind

    Searches a bib file in the BIBINPUTS paths using kpsepath (which should be
    available on most modern TeX installations). Otherwise it just returns
    the argument.

=cut

sub bibfind {
  ## since these variables are used in the _wanted sub, they need to be made global
  ## FIXME there must be a way to avoid this
  our $_filename = shift;
  our @_found = ();

  $_filename .= '.bib' unless $_filename =~ /\.(bib|xml|dbxml)$/;

  if ( can_run("kpsepath") ) {
    my $kpsepath;
    scalar run( command => [ 'kpsepath', 'bib' ],
      verbose => 0,
      buffer => \$kpsepath );
    my @paths = split ( /:!*/, $kpsepath );
    sub _removetrailingslashes {
      my $str = shift;
      $str =~ s|/+\s*$||;
      return $str
    };

    @paths = map { _removetrailingslashes( $_ ) } @paths;

    no warnings 'File::Find';
    find (\&_wanted, @paths);

    sub _wanted {
      $_ =~ /^$_filename($|\.bib$)/ && push @_found, $File::Find::name;
    }

    if (@_found) {
      my $found = shift @_found;
      $logger->debug("Found bib file $found");
      return $found ;
    } else {
      $logger->debug("Found bib file $_filename");
      return $_filename ;
    }

  } else {
    return $_filename
  }
}

=head2 parsename

    Given a name string, this function returns a hash with all parts of the name
    resolved according to the BibTeX conventions.

    parsename('John Doe') 
    returns: 
    { firstname => 'John',  
      lastname => 'Doe', 
      prefix => undef, 
      suffix => undef, 
      namestring => 'Doe, John',
      nameinitstring => 'Doe_J' }

    parsename('von Berlichingen zu Hornberg, Johann G{\"o}tz') 
    returns: 
    { firstname => 'Johann G{\"o}tz',  
      lastname => 'Berlichingen zu Hornberg', 
      prefix => 'von', 
      suffix => undef, 
      namestring => 'Berlichingen zu Hornberg, Johann Gotz',
      nameinitstring => 'Berlichingen_zu_Hornberg_JG' }

=cut

sub parsename {
  my ($namestr, $opts) = @_;
  $logger->debug("   Parsing namestring '$namestr'");
  $namestr =~ s/\\,\s*|{\\,\s*}/~/g; # get rid of LaTeX small spaces \,
  my $usepre = $opts->{useprefix};

  my $lastname;
  my $firstname;
  my $prefix;
  my $suffix;
  my $nameinitstr;

  my $PREFIXRE = qr/
                {?
                \p{Ll} # prefix starts with lowercase
                [^\p{Lu},]+ # e.g. van der
                }?
                \s+
/x ;
  my $NAMERE = qr/
                [^,]+
               |
                $RE{balanced}{-parens=>'{}'}
/x;
  my $SUFFIXRE = $NAMERE;
  my $NAMESEQRE = qr/ (?:\p{Lu}\S+[\s~]*)+ /x ;

  if ( $namestr =~ /^$RE{balanced}{-parens => '{}'}$/ )
  {
    $logger->debug("Catched namestring of type '{Some protected name string}'");
    $namestr = remove_outer($namestr);
    $lastname = $namestr;
  }
  elsif ( $namestr =~ /[^\\],.+[^\\],/ )    # pre? Lastname, suffix, Firstname
  {
    $logger->debug("Catched namestring of type 'prefix? Lastname, suffix, Firstname'");
    ( $prefix, $lastname, $suffix, $firstname ) = $namestr =~
      m/^( # prefix?
                $PREFIXRE
               )?
               ( # last name
                $NAMERE
               )
               ,
               \s*
               ( # suffix
                $SUFFIXRE
               )
               ,
               \s*
               ( # first name
                $NAMERE
               )
$/x;

    if ($lastname) {$lastname =~ s/^{(.+)}$/$1/g;} else {$logger->debug("Couldn't determine Last Name for name \"$namestr\"");}
    if ($firstname) {$firstname =~ s/^{(.+)}$/$1/g;} else {$logger->debug("Couldn't determine First Name for name \"$namestr\"");}
    $prefix =~ s/\s+$// if $prefix;
    $prefix =~ s/^{(.+)}$/$1/ if $prefix;
    $suffix =~ s/\s+$//;
    $suffix =~ s/^{(.+)}$/$1/;
    $namestr = "";
    $namestr .= "$prefix " if ($prefix && $usepre);
    $namestr .= "$lastname, $suffix, $firstname";
  }
  elsif ( $namestr =~ /[^\\],/ )   # <pre> Lastname, Firstname
  {
    $logger->debug("Catched namestring of type 'prefix? Lastname, Firstname'");
    ( $prefix, $lastname, $firstname ) = $namestr =~
      m/^( # prefix?
                $PREFIXRE
               )?
               ( # last name
                $NAMERE
               )
               ,
               \s+
               ( # first name
                $NAMERE
               )
$/x;

    if ($lastname) {$lastname =~ s/^{(.+)}$/$1/g;} else {$logger->debug("! Couldn't determine Last Name for name \"$namestr\"");}
    if ($firstname) {$firstname =~ s/^{(.+)}$/$1/g;} else {$logger->debug("! Couldn't determine First Name for name \"$namestr\"");}
    $prefix =~ s/\s+$// if $prefix;
    $prefix =~ s/^{(.+)}$/$1/ if $prefix;
    $namestr = "";
    $namestr .= "$prefix " if ($prefix && $usepre);
    $namestr .= "$lastname, $firstname";
  }
  elsif ( $namestr =~ /\s/ ) # Firstname pre? Lastname
  {
    if ( $namestr =~ /^$RE{balanced}{-parens => '{}'}.*\s+$RE{balanced}{-parens => '{}'}$/ )
    {
      $logger->debug("Catched namestring of type '{Firstname} prefix? {Lastname}'");
      ( $firstname, $prefix, $lastname ) = $namestr =~
        m/^( # first name
                    $RE{balanced}{-parens=>'{}'}
                )
                    \s+
                ( # prefix?
                    $PREFIXRE
                )?
                ( # last name
                    $RE{balanced}{-parens=>'{}'}
                )
$/x;
    }
    elsif ( $namestr =~ /^.+\s+$RE{balanced}{-parens => '{}'}$/ )
    {
      $logger->debug("Catched namestring of type 'Firstname prefix? {Lastname}'");
      ( $firstname, $prefix, $lastname ) = $namestr =~
        m/^( # first name
                    $NAMESEQRE
                )
                    \s+
                ( # prefix?
                    $PREFIXRE
                )?
                ( # last name
                    $RE{balanced}{-parens=>'{}'}
                )
$/x;
    }
    elsif ( $namestr =~ /^$RE{balanced}{-parens => '{}'}.+$/ )
    {
      $logger->debug("Catched namestring of type '{Firstname} prefix? Lastname'");
      ( $firstname, $prefix, $lastname ) = $namestr =~
        m/^( # first name
                    $RE{balanced}{-parens=>'{}'}
                )
                    \s+
                ( # prefix?
                    $PREFIXRE
                )?
                ( # last name
                    .+
                )
$/x;
    }
    else {
      $logger->debug("Catched namestring of type 'Firstname prefix? Lastname'");
      ( $firstname, $prefix, $lastname ) = $namestr =~
        m/^( # first name
                    $NAMESEQRE
                )
                 \s+
                ( # prefix?
                    $PREFIXRE
                )?
                ( # last name
                    $NAMESEQRE
                )
$/x;
    }

    if ($lastname) {$lastname =~ s/^{(.+)}$/$1/;} else {$logger->debug("! Couldn't determine Last Name for name \"$namestr\"");}
    if ($firstname) {$firstname =~ s/^{(.+)}$/$1/;} else {$logger->debug("! Couldn't determine First Name for name \"$namestr\"");}
    $firstname =~ s/\s+$// if $firstname;

    $prefix =~ s/\s+$// if $prefix;
    $prefix =~ s/^{(.+)}$/$1/ if $prefix;
    $namestr = "";
    $namestr = "$prefix " if $prefix;
    $namestr .= $lastname if $lastname;
    $namestr .= ", " . $firstname if $firstname;
  }
  else
  {    # Name alone
    $logger->debug("Catched namestring of type 'Isolated_name_string'");
    $lastname = $namestr;
  }

  #TODO? $namestr =~ s/[\p{P}\p{S}\p{C}]+//g;
  ## remove punctuation, symbols, separator and control

  $namestr =~ s/\b$NONSORTPREFIX//;
  $namestr =~ s/\b$NONSORTDIACRITICS//;

  $nameinitstr = "";
  $nameinitstr .= substr( $prefix, 0, 1 ) . " " if ( $usepre and $prefix );
  $nameinitstr .= $lastname if $lastname;
  $nameinitstr =~ s/\b$NONSORTPREFIX//;
  $nameinitstr =~ s/\b$NONSORTDIACRITICS//;
  $nameinitstr .= " " . terseinitials($suffix)
    if $suffix;
  $nameinitstr .= " " . terseinitials($firstname)
    if $firstname;
  $nameinitstr =~ s/\s+/_/g;

  return {
    namestring     => $namestr,
    nameinitstring => $nameinitstr,
    lastname       => $lastname,
    firstname      => $firstname,
    prefix         => $prefix,
    suffix         => $suffix
    }
}

=head2 makenameid

Given an array of names (as hashes), this internal sub returns a long string
with the concatenation of all names.

=cut

sub makenameid {
  my ($names) = @_;
  my @namestrings;
  foreach my $n (@{$names}) {
    push @namestrings, $n->{namestring};
  }
  my $tmp = join " ", @namestrings;
  return normalize_string_underscore($tmp, 1);
}

=head2 makenameinitid

Similar to makenameid, with the first names converted to initials.

=cut

sub makenameinitid {
  my ($names) = @_;
  my @namestrings;
  foreach my $n (@{$names}) {
    push @namestrings, $n->{nameinitstring};
  }
  my $tmp = join " ", @namestrings;
  return normalize_string_underscore($tmp, 1);
}

=head2 normalize_string

Removes LaTeX macros, and all punctuation, symbols, separators and control characters,
as well as leading and trailing whitespace.

=cut

sub normalize_string {
  my ($str, $no_decode) = @_;
  return '' unless $str; # Sanitise missing data
  $str = latex_decode($str) unless $no_decode;
  $str =~ s/\\[A-Za-z]+//g; # remove latex macros (assuming they have only ASCII letters)
  $str =~ s/[\p{P}\p{S}\p{C}]+//g; ### remove punctuation, symbols, separator and control
  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ s/\s+/ /g;
  return $str;
}

=head2 normalize_string_underscore

Like normalize_string, but also substitutes ~ and whitespace with underscore.

=cut

sub normalize_string_underscore {
  my ($str, $no_decode) = @_;
  return '' unless $str; # Sanitise missing data
  $str =~ s/([^\\])~/$1 /g; # Foo~Bar -> Foo Bar
  $str = normalize_string($str, $no_decode);
  $str =~ s/\s+/_/g;
  return $str;
}

=head2 latexescape

Escapes the LaTeX special characters { } & ^ _ $ and %

=cut

sub latexescape {
  my $str = shift;
  my @latexspecials = qw| { } & _ % |;
  foreach my $char (@latexspecials) {
    $str =~ s/^$char/\\$char/g;
    $str =~ s/([^\\])$char/$1\\$char/g;
  };
  $str =~ s/\$/\\\$/g;
  $str =~ s/\^/\\\^/g;
  return $str
}

=head2 terseinitials

terseinitials($str) returns the contatenated initials of all the words in $str.
    terseinitials('Louis Pierre de la Ramée') => 'LPdlR'

=cut

sub terseinitials {
  my $str = shift;
  return $str unless $str;
  $str =~ s/^$NONSORTPREFIX//;
  $str =~ s/^$NONSORTDIACRITICS//;
  $str =~ s/\\[\p{L}]+\s*//g; # remove tex macros
  $str =~ s/^{(\p{L}).+}$/$1/g; # {Aaaa Bbbbb Ccccc} -> A
  $str =~ s/{\s+(\S+)\s+}//g; # Aaaaa{ de }Bbbb -> AaaaaBbbbb
  # get rid of Punctuation (except DashPunctuation), Symbol and Other characters
  $str =~ s/[\x{2bf}\x{2018}\p{Lm}\p{Po}\p{Pc}\p{Ps}\p{Pe}\p{S}\p{C}]+//g;
  $str =~ s/\B\p{L}//g;
  $str =~ s/[\s\p{Pd}]+//g;
  return $str;
}

=head2 array_minus

array_minus(\@a, \@b) returns all elements in @a that are not in @b

=cut

sub array_minus {
  my ($a, $b) = @_;
  my %countb = ();
  foreach my $elem (@$b) {
    $countb{$elem}++
  };
  my @result;
  foreach my $elem (@$a) {
    push @result, $elem unless $countb{$elem}
  };
  return @result
}

=head2 remove_outer
    
    Remove surrounding curly brackets:  
        '{string}' -> 'string'

=cut

sub remove_outer {
  my $str = shift;
  $str =~ s/^{(.+)}$/$1/;
  return $str
}

=head2 getinitials
    
    Returns the initials of a name, preserving LaTeX code.

=cut

sub getinitials {
  my $str = shift;
  return '' unless $str; # Sanitise missing data
  $str =~ s/{\s+(\S+)\s+}//g; # Aaaaa{ de }Bbbb -> AaaaaBbbbb
  # remove pseudo-space after macros
  $str =~ s/{? ( \\ [^\p{Ps}\{\}]+ ) \s+ (\p{L}) }?/\{$1\{$2\}\}/gx; # {\\x y} -> {\x{y}}
  $str =~ s/( \\ [^\p{Ps}\{\}]+ ) \s+ { /$1\{/gx; # \\macro { -> \macro{
  my @words = split /\s+/, remove_outer($str);
  $str = join ".~", ( map { _firstatom($_) } @words );
  return $str . "."
}

sub _firstatom {
  my $str = shift;
  $str =~ s/^$NONSORTPREFIX//;
  $str =~ s/^$NONSORTDIACRITICS//;
  if ($str =~ /^({
                   \\ [^\p{Ps}\p{L}] \p{L}+ # {\\.x}
                   }
                   | {?
                    \\[^\p{Ps}\{\}]+        # \\macro{x}
                     { \p{L} }
                     }?
                   | { \\\p{L}+ }           # {\\macro}
)/x ) {
    return $1
  } else {
    return substr($str, 0, 1)
  }
}

=head2 tersify

    Removes '.' and '~' from initials.

    tersify('A.~B.~C.') -> 'ABC'

=cut

sub tersify {
  my $str = shift;
  $str =~ s/~//g;
  $str =~ s/\.//g;
  return $str
}

=head2 ucinit

    upper case of initial letters in a string

=cut

sub ucinit {
  my $str = shift;
  $str = lc($str);
  $str =~ s/\b(\p{Ll})/\u$1/g;
  return $str;
}

=head1 AUTHOR

François Charette, C<< <firmicus at gmx.net> >>
Philip Kime C<< <philip at kime.org.uk> >>

=head1 BUGS

Please report any bugs or feature requests on our sourceforge tracker at
L<https://sourceforge.net/tracker2/?func=browse&group_id=228270>. 

=head1 COPYRIGHT & LICENSE

Copyright 2009 François Charette and Philip Kime, all rights reserved.

This program is free software; you can redistribute it and/or
modify it under the terms of either:

=over 4

=item * the GNU General Public License as published by the Free
Software Foundation; either version 1, or (at your option) any
later version, or

=item * the Artistic License version 2.0.

=back

=cut

1;

# vim: set tabstop=2 shiftwidth=2 expandtab:
