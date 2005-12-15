=head1 NAME

 ConfigRead -- read vptk_w configuration information

=cut

package vptk_w::ConfigRead;
use Exporter 'import';
@EXPORT = qw(ReadWidgetsOptions ReadHTML ReadCnfDlgBallon);
# @EXPORT = qw(ReadWidgetsOptions _test1_); # uncomment this line for testing

use strict;

sub ReadWidgetsOptions
{
  my ($file_name) = @_; # input parameter - file name

  open(FILE,$file_name) || 
    die "$0 ConfigRead.ReadWidgetsOptions ERROR: read $file_name - $!\n";
  my $result = {};
  my $name='';
  my @data = ();
  foreach my $line (grep(!/^\s*#/,<FILE>))
  {
    $line =~ s/(^\s*)|(\s*$)//g;
    if($line=~/^\s*\w+\s*=>/)
    {
      ($name) = $line =~ /^\s*(\w+)\s*=>/;
#      print "D0: name=<$name>\n";
      next;
    }
    elsif($line=~/=>|,/)
    {
      my $tmp = $line; chomp $tmp;
      $tmp =~ s/,$//;
      $tmp =~ s/[{}']//g;
#      print "D1: data=<@data>,tmp=<$tmp>\n";
      push(@data,split(/=>|,/,$tmp));
    }
    # in some cases brackets opened and closed in same line:
    if($line =~ /\}/ && $name)
    {
      $result->{$name} = {@data};
      $name = '';
      @data = ();
    }
  }
  close FILE;

  return %$result; # output result - hash of widget parameters
}

# Read-in limited HTML format:
# 1. Text is pre-formatted
# 2. Each line associated with bold_text/regular_text/picture
#
# Return each line encoded in following format:
# <type> <line>
# type = text|bold|gif
sub ReadHTML
{
  my $file_name=shift;
  my @result=();

  open (HTML,$file_name) || return 0;
  my @file=<HTML>;
  close HTML;
  my $body=0;
  my ($line,$type);
  foreach (@file)
  {
    $body=1 if/<body/i;
    $body=0 if/<\/body>/i;
    s/.*<body[^>]+>//i;
    s/<\/body>.*//i;
    if ($body)
    {
      next if /<.?pre>/;
      $type='text';
      if(/<b>.*<\/b>/i)
      {
        $line=$_;
        $line=~s/<.?b>//ig;
        $type ='bold';
      }
      elsif(/<img src=/i)
      {
        ($line) = (/<img src=["']([^'"]+)\.gif['"]/i);  
        $type ='gif';
      }
      else
      {
        $line=$_;
        $line=~s/<[^>]+>//g;
      }
      push(@result,"$type $line");
    }
  }
  return (@result);
}

sub ReadCnfDlgBallon
{
  my ($file_name) = @_;
  return unless open(BF,$file_name);
  my $key='';
  my %cnf_dlg_ballon = ();
  while(<BF>)
  {
    chomp;
    next if /^\s*$/;
    if(/^\s*-/)
    {
      ($key,$_) = (/^\s*(-\S+)\s*=>\s*(\S.*)/);
    }
    next unless $key;
    if (defined $cnf_dlg_ballon{$key})
    {
      $cnf_dlg_ballon{$key}.="\n$_";
    }
    else
    {
      $cnf_dlg_ballon{$key}=" $key => $_";
    }
  }
  close BF;
  return (%cnf_dlg_ballon);
}

sub _test1_
{
  # my %data = &ReadWidgetsOptions(); # should fail!
  my %data = &ReadWidgetsOptions('vptk_w.attr.cfg');

  foreach my $widget(sort keys %data)
  {
    print "DEBUG: $widget=>\n";
    print "DEBUG: {".
      join(',',
        map("$_=>$data{$widget}->{$_}",keys %{$data{$widget}})
      )."}\n";
  }
}

1;
