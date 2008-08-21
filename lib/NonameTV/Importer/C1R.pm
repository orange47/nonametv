package NonameTV::Importer::C1R;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use RTF::Tokenizer;
use Locale::Recode;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/info progress error logdie 
                     log_to_string log_to_string_result/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "C1R";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  if( $file !~ /\.rtf$/ ) {
    progress( "C1R: Skipping unknown file $file" );
    return;
  }

  progress( "C1R: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  
  my $tokenizer = RTF::Tokenizer->new( file => $file );

  if( not defined( $tokenizer ) ) {
    error( "C1R $file: Failed to parse" );
    return;
  }

  my $text = '';
  my $textfull = 0;
  my $date;
  my $currdate = undef;
  my $starttime;
  my $title;
  my $havedatetime = 0;

  while( my ( $type, $arg, $param ) = $tokenizer->get_token( ) ){

    last if $type eq 'eof';

#print "--------------------------------------------------------------------\n";
#print "type: $type\n";
#print "arg: $arg\n";
#print "param: $param\n";
#print "--------------------------------------------------------------------\n";

    if( ( $type eq 'control' ) and ( $arg eq 'par' ) ){
      $textfull = 1;
    } elsif( ( $type eq 'control' ) and ( $arg eq '\'' ) ){

      $text .= chr(0x0160) if( $param eq '8a' ); # veliko S
      $text .= chr(0x017D) if( $param eq '8e' ); # veliko Z
      $text .= chr(0x0161) if( $param eq '9a' ); # malo s
      $text .= chr(0x017E) if( $param eq '9e' ); # malo z

      $text .= chr(0x0106) if( $param eq 'c6' ); # veliko mekano C
      $text .= chr(0x010C) if( $param eq 'c8' ); # veliko tvrdo C
      $text .= chr(0x0107) if( $param eq 'e6' ); # malo mekano c
      $text .= chr(0x010D) if( $param eq 'e8' ); # malo tvrdo c
      $text .= chr(0x0110) if( $param eq 'd0' ); # veliko dj
      $text .= chr(0x0111) if( $param eq 'f0' ); # malo dj

    } elsif( $type eq 'text' ){
      if( $arg =~ /^\d\d\.\d\d$/ ){
        $text = $arg;
        $textfull = 1;
      } else {
        $text .= $arg;
      }
    }

    if( $textfull )
    {

      #my $cod = Locale::Recode->new( from => 'windows-1250' , to => 'UTF-8' );
      #my $cod = Locale::Recode->new( from => 'ISO-8859-2' , to => 'UTF-8' );
      #$cod->recode( $text );

#print "TEXT: $text\n";

      if( $text eq "" ) {
        # blank line
      }
      elsif( isDate( $text ) ) { # the token with the date in format 'MONDAY 12.4.'

        $date = ParseDate( $text );

        if( defined $date ) {

          $dsh->EndBatch( 1 )
            if defined $currdate;

          my $batch_id = "${xmltvid}_" . $date->ymd();
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date->ymd("-") , "08:00" ); 
          $currdate = $date;

          progress("C1R: $chd->{xmltvid}: Date is " . $date->ymd("-") );

          $havedatetime = 0;
        }
      }
      elsif( isShow( $text ) ) { # the token with the time in format '19.30 Vremja'

	my( $starttime , $title ) = ParseShow( $text );

        progress("C1R: $chd->{xmltvid}: $starttime - $title");

        my $ce = {
          channel_id   => $chd->{id},
          start_time => $starttime,
          title => norm($title),
        };

        $dsh->AddProgramme( $ce );

        $havedatetime = 0;
      }

      $textfull = 0;
      $text = ''
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my ( $text ) = @_;

  # format 'Wednesday, August 13'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*\S+\s*\d+$/i ){
    return 1;
  }

  return 0;
}

sub isShow {
  my ( $text ) = @_;

  # format '23.00 Vremja'
  if( $text =~ /^\d+\.\d+\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  # format 'Wednesday, August 13'
  my( $dayname, $monthname, $day ) = ( $text =~ /^(\S+),\s*(\S+)\s*(\d+)$/ );

  my $year = DateTime->today->year();
  my $month = MonthNumber( $monthname , "en" );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Moscow',
  );

  return $dt;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
