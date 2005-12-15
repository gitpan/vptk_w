#!/usr/local/bin/perl

my $perl;    # which perl used for sources generation
my $path;    # where current application installed
my $toolbar; # where application resources could be found
my $os;      # what kind of OS we have: win/unix

=head1 NAME

 vptk - Perl/Tk Visual resource editor (widget edition)

=head1 SYNOPSIS

 vptk [-help]

   -h[elp]  - show this help

=head1 DEVELOPER NOTES

  1. General considerations
  =========================

  * The project supply toolkit for Perl/Tk widget-level design
 familiar with Perl/Tk
  * It can be a 'long brush' tool for user interface sketching

  2. User interface
  =================

  * All data stored in Perl/Tk include-file form
  * Widgets displayed both visually and as hierarhy tree
  * Most functions accessible both from pull-down menu,
    toolbar panel and by keyboard shortcuts

  3. Restrictions
  ===============
  * Commas and brackets prohibited inside of text fields
  * Due to known bugs in Tk some balloons not dispayed
  * No undo/redo for file options changes

  4. Main features
  ================
  * Undo for all artwork modifications
  * Unlimited undo/redo
  * Object editing using selection bars
  File: Open, New, Save, Save as, Setup, Quit
  Edit: Undo, Redo, Delete, Rename, Properties
  Create: Before, After, Subwidget
  View: Repaint, Code, Options
  * Object selection by click on view window
  * Right-button context menu on tree and view window
  * Full-functional program generation
  (use ...; mw=...; {body} MainLoop;)
  * Help & HTML documentation
  * Full menus support
  * Code generation with 'strict syntax'
  * Conflicts in geometry managers resolved automatically
  * Baloon showing code for each widget
  * X/Y mouse pointer coordinates displayed
  * Default values for most widgets apon creation
  * Default entries for lists and other arrays (display only)
  * View options: Balloons on/off, blink on/off, coord on/off
  * Arbitrary widget names on creation + rename dialog
  * Callback functions support
  * User-defined code support
  * Widget state variables
  * Automatic declaration of widget-dependent variables
  * Code portions cut-n-paste
  * Syntax highlight in code preview window
  * NumEntry used for numeric data input
  * Testing window
  * Syntax check for generated code (perl -c)
  
  5. To be implemented
  ====================
  * Cursor changes on selection/object
  * Full widgets set
  * Portions save/retrieve
  * External templates for most basic windows:
  Dialog, Configuration, Editor
  * Bindings list in File->Setup
  * Balloon assigned from 'edit menu'
  * Subroutines/variables/pictures management windows
  * Tiler as geometry manager
  * Tix->form as geometry manager (?)

  6. Known bugs
  =============
  * Double-click on HList works diffently in Unix and M$ Win
  * Bug in LabFrame and BrowseEntry not fixed - detour ;-)
  * No syntax control for callbacks, user code and variables

  7. Data structures
  ==================

  All data represented as following objects:
  - Array of all widgets descriptors
  - Nesting tree array:
  w_Frame_001
  w_Frame_001.w_Frame_002
  w_Frame_001.w_Frame_002.w_Button_001
  w_Frame_001.w_Frame_002.w_Label_001
  w_Frame_001.w_Frame_003
  w_Frame_001.w_Frame_004
  w_Frame_005
  w_Frame_006
  - Hash (Widget id) -> descriptor

  Default widget identificator: w_<WidgetType>_<0padNumber>
  Widget descriptor:
  * ID
  * Type
  * Parameters
  * Geometry info (pack/grid/place) + parameters
  * Final output ID
  * Display widget (?)

  External data representation:
  $<widget ID> = $<Parent ID> -> <Type> ( <Parameters> ) -> <Geometry>;
  Menu items (and others that can't use geometry):
  $<widget ID> = $<Parent ID> -> <Type> ( <Parameters> );

  8. Geometry conflicts and bugs in generated code
  ================================================

  What is geometry conflict? First of all it's mix of different
  geometry managers under same parent widget. Additional restriction
  (possible deviated from first one) Tk geometry manager gets
  mad if user tryes to use 'grid' geometry under frame with label.

  Solution is to detect and fix such cases in 3 potential situations:
  - widget creation
  - widget editing
  - widget move
  1st case is most trivial - newly created widget simply inherits
  geometry manager from it's 'brothers'
  In two rest cases we can detect conflict by comparison with any
  of 'brothers'. Possible solutions (we'll let user to decide):
  - Propagate conflicting geometry manager to 'brothers'
  - Adopt conflicting geometry manager according to environment
  - Cancel operation

  Yet another geometry conflict source: when some widget use
  packAdjust 'sub-widget' while 'brothers' use non-pack
  geometry managers. No solution till now (simply avoid such
  situations - otherwise your application became stuck).

  Generated program can fail on following known bugs:
  - Missed menu for Menubutton/cascade (simply don't forget it!)
  - Empty menu & -tearoff=>0 (nothing to dispay - avoid such cases!)
  - Balloon assigned to BrowseEntry/LabFrame cause error messagess 
    on double-click (in older PerlTk versions)

  ...and now documented bugs can be referred as 'feature' ;-)

  9. Menus handling
  =================

  We have two types of Menu: Menu and Menubutton
  Menubutton is the root of one Menu
  Under Menu user can create following objects:
  - Command
  - Checkbutton
  - Radiobutton
  - Separator
  - Cascade
  Under Cascade can be created any of listed objects too.

=cut

BEGIN
{
  $path=$0;
  $path=~s#[^/\\]+$##;
  $path='.' unless $path;
  unshift (@INC,$path);
  foreach($^X, '/usr/local/bin/perl', '/usr/bin/perl')
  {
    if(-f $_)
    {
      $perl = $_;
      last;
    }
  }
  $toolbar = "$path/toolbar";
  die "$0 installation error: directory $toolbar not found!\n"
    unless -d $toolbar;
  $os = 'win' unless $^O;
  $os = 'win' if $^O =~ /win/i;
  $os = 'unix' if $^O =~ /linux|unix|aix|sun|solaris/i;
}

use strict;
use Tk 800;

use Tk::DialogBox;
use Tk::Photo;
use Tk::Checkbutton;
use Tk::Balloon;
use Tk::Adjuster;
use Tk::LabFrame;
use Tk::LabEntry;
use Tk::BrowseEntry;
use Tk::NoteBook;
use Tk::HList;
use Tk::FileSelect;
use Tk::Tiler;
use Tk::ROText;
use Tk::Dialog;
use Tk::Pane;

use IPC::Open3;

# private modules:
use vptk_w::ConfigRead;
use vptk_w::ExtraWidgets;

if (grep /^--?h/,@ARGV)
{
  # for real perl script only!
  # does not work on M$ Win EXE-file
  system "perldoc $0";
  exit 1;
}

my $ver=q$Revision: 1.17 $;

my $selected;         # Currently selected widget path
my %widgets=();       # Tk widgets pointers for highlight
my $changes;          # Modifications flag
my $lastfile='';      # last file used in Open/Save
my %descriptor=();    # (id->descriptor)
my @tree=('mw');      # design tree list ('.' separated entry)
my $obj_count=0;      # counter for unique object id
my @undo=();          # Undo buffer
my @redo=();          # Redo buffer
my %cnf_dlg_ballon;   # Help messages for all widget configuration options
my (%file_opt)=(description=>'',title=>'',fullcode=>0,strict=>0);
my ($view_balloons,$view_blink,$view_pointerxy)=(1,0,0);
my @main_clipboard=();
my @user_auto_vars;
my @user_subroutines;
my @callbacks;

# and here is the table of all objects' properties
my %w_attr = &ReadWidgetsOptions("$toolbar/vptk_w.attr.cfg");

# Legal parameters per geometry:
my (%w_geom) = (
  'pack'  => [qw/-side -fill -expand -anchor -ipadx -ipady -padx -pady/],
  'grid'  => [qw/-row -column -rowspan -columnspan -sticky -ipadx -ipady -padx -pady/],
  'place' => [qw/-anchor -height -width -x -y -relheight -relwidth -relx -rely/]
);

my @LegalWidgets = (grep(&HaveGeometry($_),sort keys %w_attr),'packAdjust'); 
# (excluded widgets without geometry)
#
# ======================== Geometry management for Main window ================
# 
my $mw = MainWindow->new(-title=>"Visual Perl Tk $ver (widget edition)");
&SetMainPalette($mw,'gray90','black');
#my $mwPalette = $mw->Palette;
#my %palette=(-background=>'gray90',-foreground=>'black');

# Prepare help from HTML file:
# 1. read HTML file
my (@html_help)=(&ReadHTML("$toolbar/widget_help.html"));
@html_help = 'Sorry, help file not available!' unless $html_help[0];
# 2. get gif-files list
my @html_gifs=grep(/^gif/,@html_help);
map s/^\S+\s+//,@html_gifs;
# 3. create bold font:
$mw->fontCreate('C_bold',qw/-family courier -weight bold/);

# read in all pictures:
foreach (qw/open save new before after subwidget 
  undo redo viewcode properties delete exit cut copy paste
  packadjust button text label listbox labentry entry frame labframe optionmenu
  message scale browseentry checkbutton radiobutton menubutton cascade command
  separator notebook notebookframe justify_right justify_left justify_center
  undef fill_both fill_x fill_y
  rel_flat rel_groove rel_raised rel_ridge rel_solid rel_sunken
  anchor_center anchor_e anchor_n anchor_ne anchor_nw anchor_s anchor_se anchor_sw anchor_w
  side_bottom side_left side_right side_top/,
  @html_gifs)
{
  my $pic_file="$toolbar/$_.gif";
  $pic_file = "$toolbar/$_.xpm" unless -e $pic_file;
  $pic{$_} = $mw->Photo(-file=>$pic_file)
    unless defined $pic{$_};
}

# Read balloon messages:
%cnf_dlg_ballon = &ReadCnfDlgBallon("$toolbar/baloon_cnf_dlg.txt");

my $xy; # X=nnn Y=nnn indicator

# +-------------------------------+
# | menu ...                      |
# +-------------------------------+
# | tool bar                      |
# +------+------------------------+
# |      |                        |  
# | tree |                        |  
# | area |      drawing           |
# |      |      area              |
# |      |                        |  
# |      |                        |  
# |______|________________________|
# | status bar             x= y= *|
# +-------------------------------+
#

my $menubar = $mw->Frame(-relief => 'raised', -borderwidth => 2)
  ->form(-top=>'%0',-left=>'%0',-right=>'%100');

$menubar->Menubutton(qw/-text File -underline 0 -tearoff 0 -menuitems/ =>
  [
    [Button => '~Open ...',    -command => \&file_open, -accelerator => 'Control+o'],
    [Button => '~New',         -command => \&file_new,  -accelerator => 'Control+n'],
    [Button => '~Save',        -command => \&file_save, -accelerator => 'Control+s'],
    [Button => 'Save ~As ...', -command => [\&file_save, 'Save As']],
    [Separator => ''],
    [Button => '~Properties ...',   -command => \&file_properties],
    [Separator => ''],
    [Button => '~Quit',        -command => \&abandon,   -accelerator => 'ESC'],
  ])->pack(-side=>'left');

$menubar->Menubutton(qw/-text Insert -underline 0 -tearoff 0 -menuitems/ =>
  [
    [Button => '~Before',     -command => [\&insert,'before']],
    [Button => '~After',      -command => [\&insert,'after']],
    [Button => '~Sub-widget', -command => [\&insert,'subwidget']],
  ])->pack(-side=>'left');

$menubar->Menubutton(qw/-text Edit -underline 0 -tearoff 0 -menuitems/ =>
  [
    [Button => '~Properties', -command => \&edit_properties],
    [Separator=>''],
    [Button => '~Undo',       -command => \&undo, -accelerator => 'Control+z'],
    [Button => '~Redo',       -command => \&redo, -accelerator => 'Control+r'],
    [Separator=>''],
    [Button => '~Cut',        -command => \&edit_cut, -accelerator => 'Control+x'],
    [Button => 'C~opy',       -command => \&edit_copy, -accelerator => 'Control+c'],
    [Button => 'P~aste',      -command => \&edit_paste, -accelerator => 'Control+v'],
    [Separator=>''],
    [Button => 'R~ename',     -command => \&rename],
    [Button => '~Delete',     -command => \&edit_delete, -accelerator => 'Delete'],
  ])->pack(-side=>'left');

$menubar->Menubutton(qw/-text View -underline 0 -tearoff 0 -menuitems/ =>
  [
    [Button => '~Repaint',    -command => \&view_repaint],
    [Button => '~Code',       -command => sub{&CodePreview(&code_print)}],
    [Cascade => '~Options', -tearoff=>0, -menuitems =>
      [
        [Checkbutton=>'~Show widget balloons',
	  -variable=>\$view_balloons,-command=>\&view_repaint],
        [Checkbutton=>'~Blink widget on selection',-variable=>\$view_blink],
        [Checkbutton=>'Show ~mouse pointer X,Y coordinates',
	  -variable=>\$view_pointerxy,-command=>\&view_repaint],
	[Button => '~Re-color myself',   -command=> \&ColoringScheme ]
      ]
    ],
  ])->pack(-side=>'left');

$menubar->Menubutton(qw/-text Debug -underline 0 -tearoff 0 -menuitems/ =>
  [
    [Button => '~Edit code',    -command => \&debug_edit],
    [Button => '~Check syntax', -command => \&debug_syntax],
    [Button => '~Run code',     -command => \&debug_run],
  ])->pack(-side=>'left');

$menubar->Menubutton(qw/-text Help -underline 0 -tearoff 0 -menuitems/ =>
  [
     [Button => 'VPTk ~help',       -command => [\&ShowHelp,@html_help]],
     [Button => '~Context help',    -command => \&tkpod],
     [Cascade => '~PerlTk manuals', -tearoff=>0, -menuitems =>
       [
         [Button => '~Overview',          -command => [\&tkpod,'overview']],
         [Button => '~Standard options',  -command => [\&tkpod,'options']],
         [Button => 'Option ~handling',   -command => [\&tkpod,'option']],
         [Button => 'Tk ~variables',      -command => [\&tkpod,'tkvars']],
         [Button => '~Grab manipulation', -command => [\&tkpod,'grab']],
         [Button => '~Binding',           -command => [\&tkpod,'bind']],
         [Button => 'Bind ~tags',         -command => [\&tkpod,'bindtags']],
         [Button => '~Callbacks',         -command => [\&tkpod,'callbacks']],
         [Button => '~Events',            -command => [\&tkpod,'event']],
       ]
     ],
     [Button => '~About',     -command => [\&ShowAboutMessage,$ver]],
  ])->pack(-side=>'right');

# pop-up menu on right button

my $popup=$mw->Menu(-tearoff=>0);
my $popup_insert=$popup->Menu(-tearoff=>0);
$popup_insert->add('command',-label=>'Before',-underline=>0,-command=>[\&insert,'before']);
$popup_insert->add('command',-label=>'After',-underline=>0,-command=>[\&insert,'after']);
$popup_insert->add('command',-label=>'Subwidget',-underline=>0,-command=>[\&insert,'subwidget']);
$popup->add('cascade',-label=>'Insert',-underline=>0,-menu=>$popup_insert);
$popup->add('command',-label=>'Properties',-underline=>0,-command=>\&edit_properties);
$popup->add('command',-label=>'Context help',-underline=>8,-command=>\&tkpod);
$popup->add('command',-label=>'Cut',-underline=>0,-command=>\&edit_cut,-accelerator => 'Control+x');
$popup->add('command',-label=>'Copy',-underline=>1,-command=>\&edit_copy,-accelerator => 'Control+c');
$popup->add('command',-label=>'Paste',-underline=>1,-command=>\&edit_paste,-accelerator => 'Control+v');
$popup->add('command',-label=>'Rename',-underline=>0,-command=>\&rename);
$popup->add('command',-label=>'Delete',-underline=>0,-command=>\&edit_delete,-accelerator => 'Delete');

my $bf=$mw->Frame()->
form(-top=>$menubar,-left=>'%0',-right=>'%100',-bottom=>'%100');
# ===============
# 'buttons' frame
# ===============
my $ctrl_frame=$bf->Frame()->pack(-side=>'top',-anchor=>'nw');
my $main_frame=$bf->Frame()
  ->pack(-side=>'top',-anchor=>'ne',-fill=>'both',-expand=>1);
my $status_frame=$bf->Frame(-relief=>'groove')
  ->pack(-side=>'top',-anchor=>'nw',-fill=>'x');
my $status=$status_frame->Label(-text=>'No selection',-relief=>'sunken',-borderwidth=>2)
  ->pack(-side=>'left');
my $changes_l=$status_frame->Label(-text=>' ',-relief=>'sunken',-borderwidth=>2)
  ->pack(-side=>'right');
$status_frame->Label(-textvariable=>\$xy,-relief=>'sunken',-borderwidth=>2,-width=>11)
  ->pack(-side=>'right',-padx=>10);
&changes(0);
# ==========
# ctrl_frame
# ==========
$b=$mw->Balloon(-background=>'lightyellow',-initwait=>550);

my @buttons = 
(
  ['new',      \&file_new,            'New project'],
  ['open',     \&file_open,           'Open file'],
  ['save',     \&file_save,           'Save current file'],
  [0],
  ['before',   [\&insert,'before'],   'Insert new widget before'],
  ['after',    [\&insert,'after'],    'Insert new widget after'],
  ['subwidget',[\&insert,'subwidget'],'Insert new subwidget'],
  [0],
  ['undo',     \&undo,                'Undo last change'],
  ['redo',     \&redo,                'Redo last change'],
  [0],
  ['delete',   \&edit_delete,         'Erase selected'],
  ['cut',      \&edit_cut,            'Cut selected tree to clipboard'],
  ['copy',     \&edit_copy,           'Copy selected tree to clipboard'],
  ['paste',    \&edit_paste,          'Paste from clipboard before selected'],
  ['properties',\&edit_properties,    'View & edit properties'],
  [0],
  ['viewcode', sub{&CodePreview(&code_print)}, 'Preview generated code'],
  [0],
  ['exit',     \&abandon,             'Exit program'],
);
foreach my $button(@buttons)
{
  if($button->[0])
  {
    $b->attach($ctrl_frame->
      Button(-image=>$pic{$button->[0]}, -command=>$button->[1])->
      pack(-side=>'left',-expand=>1),-balloonmsg=>$button->[2]);
  }
  else
  {
    $ctrl_frame->Label(-text=>' ')->pack(-side=>'left',-expand=>1);
  }
}

my $tf=$main_frame->Scrolled('HList', -scrollbars=>'se',-itemtype=>'imagetext')
  ->pack(-side=>'left',-fill=>'y');
$tf->bind('<Button-1>', 
  sub{ &set_selected($tf->info('data',$tf->infoSelection)); } );
#  sub{ &set_selected($tf->nearest($tf->pointery-$tf->rooty)); } );
$tf->configure(
  -command  => sub{&set_selected($tf->info('data',$tf->infoSelection));&edit_properties},
  -browsecmd=> sub{&set_selected($tf->info('data',$tf->infoSelection));} );
$tf->add('mw',-text=>'mw',-data=>'mw',-image=>$pic{lc('Frame')});

my $w;
&clear_preview(); # this will initialize preview vindow
$tf->packAdjust(-side=>'left');

$tf->bind('<Button-3>',
  sub{ &set_selected($tf->nearest($tf->pointery-$tf->rooty)); $popup->Post($mw->pointerxy)});
$mw->bind('<Control-o>',\&file_open);
$mw->bind('<Control-s>',\&file_save);
$mw->bind('<Control-n>',\&file_new);
$mw->bind('<Control-z>',\&undo);
$mw->bind('<Control-r>',\&redo);
$mw->bind('<Delete>',\&edit_delete);
$mw->bind('<Control-x>',\&edit_cut);
$mw->bind('<Control-c>',\&edit_copy);
$mw->bind('<Control-v>',\&edit_paste);
$mw->bind('<F1>',[\&ShowHelp,@html_help]);
$mw->bind("<Escape>", \&abandon);
$mw->geometry('=600x500+120+1'); # initial window position

$mw->protocol('WM_DELETE_WINDOW',\&abandon);

$mw->SelectionOwn(-selection=>'CLIPBOARD');

&file_read(@ARGV) if scalar(@ARGV);
&view_repaint; # force repaint!
&set_selected('mw');

MainLoop;

print "We are not supposed to be here...\n";

######################################################
#     SUBROUTINES section
######################################################
sub ColoringScheme
{
  my ($bg_color,$fg_color)=&GetMainPalette();
  
  my $db=$mw->DialogBox(-title=>'Choose color scheme:',-buttons=>[qw/Ok Default Dismiss/]);
  my $f;
  $f=$db->Frame->pack(-padx=>6,-pady=>6);
  &ColorPicker($f,'Background',\$bg_color);
  $f=$db->Frame->pack(-padx=>6,-pady=>6);
  &ColorPicker($f,'Foreground',\$fg_color);
  my $reply = $db->Show;
  return if $reply eq 'Dismiss';
  ($bg_color,$fg_color)=(qw/gray90 black/) if $reply eq 'Default';
  &SetMainPalette($mw,$bg_color,$fg_color);
  # Re-paint preview window:
  &view_repaint; # force repaint!
}

sub ColorPicker
{
  my($f,$text,$p,$checkbutton)=@_;
  my $cl=$f->Menubutton(-text=>$text,-relief=>'raised')
    ->pack(-side=>'right', -padx=>7);
  my $m = $cl->Menu(qw/-tearoff 0/);
  my $var=($$p)?1:0;
  my $i=1;
  foreach (qw/Brown Red pink wheat2 orange 
	Yellow DarkKhaki LightSeaGreen Green DarkSeaGreen 
	green4 DarkGreen Cyan LightSkyBlue Blue 
	NavyBlue plum magenta1 Magenta3 purple3 
        White gray90 gray75 gray50 Black/)
  {
    $m->command(-label => $_, -columnbreak=>(($i-1) % 5)?0:1,
      -command=>
      [sub{$$p=shift;$var=1;$cl->configure(-background=>$$p)},$_]);
    my $i1 = $m->Photo(qw/-height 16 -width 16/);
    $i1->put(qw/gray50 -to 0 0 16 1/);
    $i1->put(qw/gray50 -to 0 1 1 16/);
    $i1->put(qw/gray75 -to 0 15 16 16/);
    $i1->put(qw/gray75 -to 15 1 16 15/);
    $i1->put($_, qw/-to 1 1 15 15/);
    $m->entryconfigure($i, -image => $i1);
    $i++;
  }
  $cl->configure(-menu => $m);
  $cl->configure(-background=>$$p,-activebackground=>$$p,
    -highlightbackground=>$$p,-state=>'active') 
    if $$p;
  if($checkbutton)
  {
    my $cb=$f->Checkbutton(-text => 'enabled',
      -relief => 'solid',-variable=>\$var,-borderwidth=>0,
      -command => sub{ $$p='' unless $var; }
     )->pack(-side=>'right', -padx=>7);

  }
}

sub debug_do
{
  return &ShowDialog(-title=>'Debug',-bitmap=>'error',-text=> "File not saved!\n")
    if $changes;
  return &ShowDialog(-title=>'Debug',-bitmap=>'error',-text=> "Your design is empty!\n")
    if scalar(@tree) == 1;
  my ($str,$title)=@_;
  my $filepath=$lastfile;
  
  if($os eq 'unix')
  {
    $filepath="$ENV{PWD}/$filepath" unless $filepath=~/^\//;
  }

  $str=~s/\$filepath/$filepath/g;
  if($os eq 'unix')
  {
    $title="-T '$title' " if $title;
    system("xterm $title -e $str");
  }
  else
  {
    my @log = ();
    open3(\*WTRFH, \*RDRFH, \*ERRFH, $str);
    push(@log,map("text $_",<RDRFH>));
    push(@log,map("bold $_",<ERRFH>));
    close WTRFH; close RDRFH; close ERRFH;
    chomp @log;
    # show results if log generated
    &ShowHelp(@log) if @log;
  }
}

sub debug_edit
{
  my $editor=$ENV{'EDITOR'} || 'vi';
  my $run_str = ($os eq 'unix')?
    "$editor \$filepath &" : "$editor \$filepath";
  &debug_do($run_str,'Editing');
}

sub debug_syntax
{
  my $run_str = ($os eq 'unix')?
    "csh -c '$perl -c \$filepath | less'" : "$perl -c \$filepath";
  &debug_do($run_str,'Syntax check');
}

sub debug_run
{
  my $run_str = ($os eq 'unix')?
    "csh -c '$perl -w \$filepath | less'" : "$perl -w \$filepath";
  &debug_do($run_str);
}

sub HaveGeometry # those widgets placed without geometry manager
{
  return ! grep($_[0] eq $_,
    qw/Menu command radiobutton checkbutton cascade separator NoteBookFrame packAdjust/);
}

sub Tk::Error
{
  my ($widget,$error,@locations) = @_;
  print "DEBUG: widget <$widget> error <$error> from <@locations>\n";
}

sub clear_preview
{
  eval{map($b->detach($_),values %widgets)};
  # we use "eval" here in order to skip irrelevant error messages from "detach"
  if (Exists($w))
  {
    # unbind here?
    $w->destroy();
  }
  %widgets=();
  $xy='';
  $w=$main_frame->Scrolled('Frame',-relief=>'sunken',-borderwidth=>2) 
    ->pack(-fill=>'both',-expand=>1);
  &bind_xy_move($w);
}

sub bind_xy_move
{
  shift->bind('<Motion>',
    sub{my($x,$y)=$w->pointerxy;$x-=$w->rootx;$y-=$w->rooty;$xy="x=$x y=$y"})
    if $view_pointerxy;
}

sub view_repaint
{
  &clear_preview();
  my %tmp_vars=('mw'=>$w); # those variables exist only for 'redraw' window
  # widgets connectivity
  foreach my $path(@tree)
  {
    my $id=&path_to_id($path);
    next unless defined $descriptor{$id};
    next if $id eq 'mw';
    my $d=$descriptor{$id};
    my $x=$tmp_vars{$d->{'parent'}};
    my @arg=&split_opt($d->{'opt'});
    if(grep(/(-command|-\w+cmd)/,@arg))
    {
      my (%arg)=@arg;
      foreach my $par(qw/command createcmd raisecmd/)
      {
        $arg{"-$par"}=[\&callback,$arg{"-$par"}] if $arg{"-$par"};
      }
      (@arg)=(%arg);
    }
    if   ($d->{'type'} eq 'Frame')   { $tmp_vars{$id} = $x->Frame(@arg); }
    elsif($d->{'type'} eq 'Text')    { $tmp_vars{$id} = $x->Text(@arg); }
    elsif($d->{'type'} eq 'Entry')   { $tmp_vars{$id} = $x->Entry(@arg); }
    elsif($d->{'type'} eq 'Message') { $tmp_vars{$id} = $x->Message(@arg); }
    elsif($d->{'type'} eq 'BrowseEntry')   { 
      my (%arg)=@arg;
      my $lpack= delete $arg{'-labelPack'};
      $lpack=~s/[\[\]']//g;
      $tmp_vars{$id} = $x->BrowseEntry((%arg),-choices=>[qw/one two three/],
       -labelPack=>[&split_opt($lpack)]); }
    elsif($d->{'type'} eq 'LabEntry'){ 
      my (%arg)=@arg;
      my $lpack= delete $arg{'-labelPack'};
      $lpack=~s/[\[\]']//g;
      $tmp_vars{$id} = $x->LabEntry(%arg,-labelPack=>[&split_opt($lpack)]); 
    }
    elsif($d->{'type'} eq 'LabFrame'){ $tmp_vars{$id} = $x->LabFrame(@arg); }
    elsif($d->{'type'} eq 'Label')   { $tmp_vars{$id} = $x->Label(@arg); }
    elsif($d->{'type'} eq 'Listbox') { $tmp_vars{$id} = $x->Listbox(@arg);
      $tmp_vars{$id}->insert('end', qw/item1 item2 item3/);}
    elsif($d->{'type'} eq 'packAdjust')   { $tmp_vars{$id} = $x->packAdjust(@arg); }
    elsif($d->{'type'} eq 'Scale')   { $tmp_vars{$id} = $x->Scale(@arg); }
    elsif($d->{'type'} eq 'Optionmenu'){ 
      $tmp_vars{$id} = $x->Optionmenu(-options=>[qw/one two three/]); }
    elsif($d->{'type'} eq 'Button')  { $tmp_vars{$id} = $x->Button(@arg); }
    elsif($d->{'type'} eq 'Radiobutton')  { $tmp_vars{$id} = $x->Radiobutton(@arg); }
    elsif($d->{'type'} eq 'Checkbutton')  { $tmp_vars{$id} = $x->Checkbutton(@arg); }
    elsif($d->{'type'} eq 'Menubutton')  { $tmp_vars{$id} = $x->Menubutton(@arg); }
    elsif($d->{'type'} eq 'cascade')  { $tmp_vars{$id} = $x->cascade(@arg); }
    elsif($d->{'type'} eq 'command')  { $tmp_vars{$id} = $x->command(@arg); }
    elsif($d->{'type'} eq 'checkbutton')  { $tmp_vars{$id} = $x->checkbutton(@arg); }
    elsif($d->{'type'} eq 'radiobutton')  { $tmp_vars{$id} = $x->radiobutton(@arg); }
    elsif($d->{'type'} eq 'separator')  { $tmp_vars{$id} = $x->separator(@arg); }
    elsif($d->{'type'} eq 'NoteBook')  { $tmp_vars{$id} = $x->NoteBook(@arg); }
    elsif($d->{'type'} eq 'NoteBookFrame')  { $tmp_vars{$id} = $x->add($id,@arg); }
    elsif($d->{'type'} eq 'Menu')  {
      # For cascade-based Menu use root menu widget in place of $x:
      my $root_menu=$x;
      $root_menu=$tmp_vars{$descriptor{$d->{'parent'}}->{'parent'}}
        if $descriptor{$d->{'parent'}}->{'type'} eq 'cascade';
      $tmp_vars{$id} = $root_menu->Menu(@arg); 
      $x->configure(-menu=>$tmp_vars{$id}); }
    else{print "ERROR: widget of type ".$d->{'type'}." can't be displayed!\n";}

    if(&HaveGeometry($d->{'type'}))
    {
      my ($geom,$geom_opt)=(split '[)(]',$d->{'geom'});
      my $balloonmsg=&code_line_print($path);
      $balloonmsg =~ s/ -> / ->\n/g;

      $b->attach($tmp_vars{$id},-balloonmsg=>$balloonmsg)
       if $view_balloons && 
         $d->{'type'} !~ /^(BrowseEntry|LabFrame)$/; # bug in BrowseEntry/LabFrame?
      $tmp_vars{$id}->bind('<Button-3>',
        sub{&set_selected($tf->info('data',$path));$popup->Post($mw->pointerxy)});
      $tmp_vars{$id}->bind('<Button-1>',
        sub{&set_selected($tf->info('data',$path))});
      $tmp_vars{$id}->bind('<Double-1>',
        sub{&set_selected($tf->info('data',$path));&edit_properties});
      &bind_xy_move($tmp_vars{$id});
      if($geom eq 'pack')
      {
        $tmp_vars{$id}->pack(&split_opt($geom_opt));
      }
      elsif($geom eq 'grid')
      {
        $tmp_vars{$id}->grid(&split_opt($geom_opt));
      }
      elsif($geom eq 'place')
      {
        $tmp_vars{$id}->place(&split_opt($geom_opt));
      }
    }
    $widgets{$path}=$tmp_vars{$id};
  }
  $widgets{'mw'}=$w;
}

sub file_properties
{
  my $db = $mw->DialogBox(-title=>'File setup',-buttons=>['Ok','Cancel']);
  my (@p)=(qw/-sticky we -padx 20 -pady 10 -column 0/);

  # copy options
  my (%new_opt)=(%file_opt);

  my $row=0;
  $db->LabEntry(-label=>'Program description:',-width=>45,
    -textvariable=>\$new_opt{'description'})->grid(@p,-row=>$row++);
  $db->LabEntry(-label=>'Window title:',-width=>45,
    -textvariable=>\$new_opt{'title'})->grid(@p,-row=>$row++);
  $db->Checkbutton(-text=>'Generate full executable program',-anchor=>'w',
    -variable=>\$new_opt{'fullcode'})->grid(@p,-row=>$row++);
  $db->Checkbutton(-text=>'Use strict output syntax',-justify=>'left',-anchor=>'w',
    -variable=>\$new_opt{'strict'})->grid(@p,-row=>$row++);
  my $frm=$db->LabFrame(-labelside=>'acrosstop',-label=>'User code (callbacks)')
    ->grid(@p,-row=>$row++);
  my $txt=$frm->Scrolled(qw/Text -scrollbars oe -height 15 -background white/,
    -foreground=>'black'#$palette{'-foreground'}
    )->pack();
  my $signature=(@user_subroutines) ?
    shift(@user_subroutines) : '#===vptk end===< DO NOT CODE ABOVE THIS LINE >===';
  map($txt->insert('end',"$_\n"),@user_subroutines);
  $db->bind('<Key-Return>',undef);
  $db->resizable(1,0);
  &Coloring($db); #$db->RecolorTree($Palette);
  # show dialog
  my $reply=$db->Show();

  (@user_subroutines)=($signature,@user_subroutines);
  return if $reply eq 'Cancel';

  # apply new options
  (%file_opt) = (%new_opt);

  (@user_subroutines)=($signature,split("\n",$txt->get('0.0','end')));
  
  map(&PushCallback(/sub\s+([^\s\{]+)/),@user_subroutines);

  &changes(1); # can't store undo info so far!
}

sub file_new
{
  # check for save status here!

  return unless &check_changes;

  &struct_new;
  &changes(0);
  &view_repaint; # force repaint!
  @redo=(); @undo=(); # clear undo/redo stacks
  @user_subroutines=();
  (%file_opt)=(description=>'',title=>'',fullcode=>0,strict=>0);
}

sub struct_new
{
  #________________________________
  # widget section:
  &clear_preview();
  # clean tree widget:
  $tf->delete('all');
  $tf->add('mw',-text=>'mw',-data=>'mw',-image=>$pic{lc('Frame')});
  #________________________________
  # data section:
  @tree=('mw');
  foreach my $id (keys %descriptor)
  {
    undef %{$descriptor{$id}} if(ref $descriptor{$id});
    delete $descriptor{$id};
  }
  %widgets=();
  @user_auto_vars=();
  @callbacks=();
}

sub set_selected
{
  $selected = shift;
  $status->configure(-text=>"Selected: $selected");
  # highlight respective object:
  return unless defined $widgets{$selected};
  $tf->anchorClear(); $tf->selectionClear();
  $tf->anchorSet($selected); $tf->selectionSet($selected);
  return unless $view_blink; # return here if no blink
  return unless &HaveGeometry($descriptor{&path_to_id($selected)}->{'type'});
  my $sw=$widgets{$selected};
  my $saved=$sw->cget(-background);
  foreach my $color(qw/white black yellow blue/)
  {
    Tk::DoOneEvent(0);$mw->after(20);
    last unless $sw->Exists();
    $sw->configure(-background=>$color);
    Tk::DoOneEvent(0);$mw->after(20);
    last unless $sw->Exists();
    $sw->configure(-background=>$saved);
  }
}

sub changes
{
  $changes=shift;
  $changes_l->configure(-text=> ($changes)?'*':' ');
  if ($changes)
  {
    # resolve conflicts:
    # -----------------
    # conflict No 1 - remove Label from Frame with grid sub-widgets
    #   for each frame widget
    #   get all children id's
    #   get those geometry
    #   remove -label if at least one match 'grid'
    foreach my $elm(@tree)
    {
      my ($id) = ($elm=~/\.([^\.]+)$/);
      next unless $descriptor{$id}->{'type'} eq 'Frame';
      my (@children)=grep(/\.$id\.([^\.]+)$/,@tree);
      next unless @children;
      map {s/.*\.//} @children;
      map {$_=$descriptor{$_}->{'geom'}} @children;
      if ( grep (/grid/,@children) )
      {
        my (%opt)=&split_opt($descriptor{$id}->{'opt'});
	if ($opt{'-label'})
	{
	  delete $opt{'-label'};
	  $descriptor{$id}->{'opt'} = join(', ',%opt);
	}
      }
    }
    &view_repaint;
  }
}

sub abandon
{
  return unless &check_changes;
  exit;
}

sub check_changes
{
  if($changes)
  {
    # ask for save
    
    my $reply=&ShowDialog(-bitmap=>'question',
     -text=>"File not saved!\nDo you want to save the changes?",
        -title => "You have some changes", 
        -buttons => ['Save','Don\'t save', 'Cancel']);
    if($reply eq 'Save')
    {
      $reply=&file_save('Save As');
    }
    return 0 if($reply eq 'Cancel');
  }
  return 1; # Ok
}

sub file_save
{
  my ($type)=shift;
  unless($type)
  {
    return unless $changes;
  }
  $mw->Busy;
  # open file save dialog box
  my $file = $lastfile;
  $file=~s#.*[/\\]([^/\\]+)$#$1#;
  if(! -f $lastfile || $type)
  {
    $file='newfile.pl';
    if($os eq 'win')
    {
      my @types = ( ["Perl files",'.pl'], ["All files", '*'] );
      $file = $mw->getSaveFile(-filetypes => \@types,
                          -initialfile => $file,
                          -defaultextension => '.pl',
                          -title=>'file to save');
    }
    else
    {
      $file = $mw->FileSelect(-directory => '.',
                          -initialfile => $file,
                          -title=>'file to save')->Show;
    }
  }
  $mw->Unbusy;
  # return 'Cancel' if file not selected
  return 'Cancel' unless($file);
  $lastfile=$file;

  # save data structure to file
  unless(open (DATA,">$file"))
  {
    # report error
    &ShowDialog(-title=>'Error:',-text=>"File $file write - $!\n",-buttons=>['Continue']);
    return 'Cancel';
  }
  else
  {
    my ($strict,$my)=('','');
    ($strict,$my)=("use strict;\n",'my ') if $file_opt{'strict'};
    if($file_opt{'fullcode'})
    {
      # get full widgets list:
      my %Widgets;
      foreach my $k(keys %descriptor)
      {
        my $t=$descriptor{$k}->{'type'};
	next if $t =~ /^(command|checkbutton|radiobutton|separator|cascade)$/;
	next unless $t;
	$t='Adjuster' if $t eq 'packAdjust';
	$t='NoteBook' if $t eq 'NoteBookFrame';
        $Widgets{$t}=1;
      }
      my $used;
      map ($used.="use Tk::$_;\n",sort keys %Widgets);
      print DATA "#!$perl\n\n".
      "# $file_opt{description}\n\n".
      "${strict}use Tk;\n$used\n".
      "$my\$mw=MainWindow->new(-title=>'$file_opt{title}');\n";
    }
    @user_auto_vars=();
    foreach my $element(@tree)
    {
      my $d=$descriptor{&path_to_id($element)};
      next unless $d;
      my ($user_var)=($d->{'opt'}=~/variable[^\$]+\\\$(\w+)/);
      push(@user_auto_vars,$user_var) 
        if $user_var && ! grep($_ eq $user_var,@user_auto_vars);
    }
    print DATA "\nuse vars qw/\$".join(' $',@user_auto_vars)."/;\n\n" if @user_auto_vars;
    print DATA join("\n",&code_print());
    if($file_opt{'fullcode'})
    {
      print DATA "\nMainLoop;\n";
    }

    if(@user_subroutines)
    {
      print (DATA "\n",join("\n",@user_subroutines),"\n");
    }
    else
    {
      print DATA "\n#===vptk end===< DO NOT CODE ABOVE THIS LINE >===\n";
    }
    close DATA;
  }
  # reset changes flag
  &changes(0);
  return 0;
}

sub file_open
{
  &file_new();

  $mw->Busy;
  # open file save dialog box
  my $file = $lastfile;
  $file=~s#.*[/\\]([^/\\]+)$#$1#;
  if($os eq 'win')
  {
    my @types = ( ["Perl files",'.pl'], ["All files", '*'] );
    $file = $mw->getOpenFile(-filetypes => \@types,
      -initialfile => $file, -defaultextension => '.pl',
      -title=>'file to read');
  }
  else
  {
    $file = $mw->FileSelect(-directory => '.',
      -initialfile => $file, -title=>'file to read')->Show;
  }
  $mw->Unbusy;
  # return 'Cancel' if file not selected
  return 'Cancel' unless($file);
  &file_read($file);
}

sub file_read # read file and convert to internal data
{
  my ($file)=(@_);
  $lastfile=$file;

  my (@file);

  unless(open (DATA,$file))
  {
    # report error
    &ShowDialog(-title=>'Error:',-text=>"File $file read - $!\n",-buttons=>['Continue']);
    return 'Cancel';
  }
  # else
  &file_new();
  &struct_read(<DATA>);
  &view_repaint;
  close DATA;
}

# Clipboard operations implementation

# 1. Clibpoard data consistency (check for signature line)
# 2. All clipboard operations can be performed on single
#    widget selection (and all it's sub-widgets)
# 3. When placing to clipboard the data must be 'transferred'
#    to root hierarhy level by substitution of 'parent' for
#    selected widget
# 4. While pasting data from clipboard 1st of all must be
#    checked selected (to be inserted) widget type. If it 
#    contradict to paste context - operation cancelled with
#    error box.
# 5. Next check is for possible geometry management conflicts 
#    between widget to be inserted and context. User can
#    choose one of following: 'propagate' | 'adopt' | 'cancel'
# 6. Last check must be done per widget to be inserted:
#    does it's ID conflicting with existing widgets?
#    In case of conflict operation must be cancelled
#    (no ugly automatic names!)

sub edit_cut 
{
  return if $selected eq 'mw';
  # store selected:
  &edit_copy;
  # delete selected:
  &edit_delete;
}

sub edit_copy
{
  return if $selected eq 'mw';
  my $id=&path_to_id($selected);
  #$mw->clipboardClear();
  #$mw->SelectionClear(-selection => 'CLIPBOARD');
  @main_clipboard=();
  push (@main_clipboard,join('|','#VPTK_W',$descriptor{$id}->{'parent'},$id,
    $descriptor{$id}->{'type'},$descriptor{$id}->{'geom'}));
  # get all IDs of copied widgets:
  my @copy_id=grep(/(^|\.)$id(\.|$)/,@tree);
  map (s#^.*\.##,@copy_id);
  push (@main_clipboard,'#'.join('|',@copy_id));
  grep (push(@main_clipboard,&code_line_print($_)),@copy_id);
  #$mw->clipboardAppend(join("\n",@clipboard));
}

sub edit_paste
{
  return if $selected eq 'mw';
  my $id=&path_to_id($selected);
  my @clipboard=@main_clipboard;
  #@clipboard = split(/\n/,$mw->SelectionGet(-selection => 'CLIPBOARD'));
  # check for signature:
  unless ($clipboard[0]=~/^#VPTK_W\|/)
  {
    &ShowDialog(-bitmap=>'error',-text=> "Clipboard is empty or corrupt!");
    return;
  }
  # check type conflict:
  my $parent=$descriptor{$id}->{'parent'};
  my $parent_type=$descriptor{$parent}->{'type'};
  $clipboard[0]=~s/^#VPTK_W\|//;
  my ($clp_parent,$clp_id,$clp_type,$clp_geom)=split(/\|/,shift(@clipboard));
  if(
    ($clp_type eq 'NoteBookFrame' && $parent_type ne 'NoteBook') ||
    ($clp_type eq 'Menu' && $parent_type !~ /^(Menubutton|cascade)$/) ||
    ($parent_type ne 'Menu' && $clp_type =~ 
      /^(cascade|command|checkbutton|radiobutton|separator)$/))
  {
    &ShowDialog(-bitmap=>'error',-text=> 
      "Clipboard <-> destination type conflict ($clp_type,$parent_type)!");
    return;
  }
  # check name conflict:
  $clipboard[0]=~s/^#//;
  foreach (split(/\|/,$clipboard[0]))
  {
    if(defined $descriptor{$_})
    {
      &ShowDialog(-bitmap=>'error',
        -text=> "Can't paste $_ from clipboard - this ID already used!");
      return;
    }
  }
  my $reply='';
  # check geometry conflict:
  if($clp_geom)
  {
    my $clp_geom_patt=$clp_geom;
    $clp_geom_patt=~s#\(.*$##;
    my (@brothers)=&tree_get_sons($parent);
    # get their geometry
    map ( $_=$descriptor{$_}->{'geom'} , @brothers );
    if (grep(!/^$clp_geom_patt/,@brothers))
    {
      # if any of brothers does not match:
      # Ask user about possible conflict solution
      # 'Propagate' | 'Adopt' | 'Cancel'
      # return on 'Cancel'
      my $eb = $mw->DialogBox(-title=>'Geometry conflict!',
        -buttons=>[qw/Propagate Adopt Cancel/]);
      $eb->Label(-justify=>'left',-text=>"Geometry <$clp_geom> of clipboard widget conflicts with\n".
      "other sub-widgets of $parent :\n".
      join(' ',grep(!/^$clp_geom_patt/,@brothers)).
      "\n\n   Now you can:\n".
      " Propagate this geometry to neighbor widgets\n".
      " Adopt current widget geometry to it's neighbors\n".
      " or Cancel paste operation")->pack();
      $eb->resizable(1,0);
      &Coloring($eb);
      $reply = $eb->Show();
      return if $reply eq 'Cancel';
    }
  }
  shift(@clipboard);
  $clipboard[0] =~ s/\$($clp_parent)(\W)/\$$parent$2/g; # rename parent for inserted root
  # Save undo information:
  &undo_save();
  # insert here:
  my (@save_tree)=splice(@tree,&index_of($id));
  &struct_read(@clipboard);
  push (@tree,@save_tree);
  if ($reply eq 'Propagate')
  {
    foreach (&tree_get_brothers($clp_id)) { $descriptor{$_}->{'geom'}=$descriptor{$clp_id}->{'geom'} }
  }
  if ($reply eq 'Adopt')
  {
    $descriptor{$clp_id}->{'geom'} = $descriptor{(&tree_get_brothers($clp_id))[0]}->{'geom'}
  }
  # repaint tree:
  $tf->delete('all');
  $descriptor{'mw'}->{'type'}='Frame';
  grep ( $tf->add($_,-text=>&path_to_id($_),-data=>$_,
    -image=>$pic{lc($descriptor{&path_to_id($_)}->{'type'})}), @tree );
  delete $descriptor{'mw'};
  &changes(1);
  &set_selected($selected);
}

sub edit_delete
{
  if ($selected eq 'mw') # say something to user here:
  {
    &ShowDialog(-title=>'Error',-text=>'Use File->New in order to clear all');
    return;
  }
  # save current state for undo
  &undo_save();
  # 1. remove internal structures (including sub-widgets)
  foreach my $d (grep(/$selected/,@tree))
  {
    my $id=$d; $id=~s/.*\.//;
    undef %{$descriptor{$id}} if(ref $descriptor{$id});
    delete $descriptor{$id};
  }
  @tree = grep(!/$selected/,@tree);
  # 2. remove from tree
  $tf->delete('entry',$selected);
  &set_selected('mw');
  $tf->selectionSet($selected);
  &changes(1);
}

sub insert
{
  my ($where)=shift; # 'before' | 'after' | 'subwidget'

  return if($selected eq 'mw' && $where ne 'subwidget');
  # 1. ask for widget type
  my $db=$mw->DialogBox(-title => "Create $where $selected",-buttons=>['Ok','Cancel']);
  my @LegalW=@LegalWidgets;
  # determine where insertion point is
  # if it's menu/menubutton/cascade - change LegalW to respective array
  # Menubutton -> Menu
  # Menu,cascade -> cascade,command,checkbutton,radiobutton,separator
  {
    my $parent=&path_to_id($selected);
    $parent = $descriptor{$parent}->{'parent'}
      if($where ne 'subwidget');  # go up one level
    @LegalW=('Menu') 
      if($descriptor{$parent}->{'type'} =~ /^(Menubutton|cascade)$/);
    @LegalW=(qw/cascade command checkbutton radiobutton separator/) 
      if($descriptor{$parent}->{'type'} eq 'Menu');
    if($descriptor{$parent}->{'type'} eq 'NoteBook')
    {
      &do_insert($where,'NoteBookFrame');
      return;
    }
    return 
      if $descriptor{$parent}->{'type'} =~ /^(command|checkbutton|radiobutton|separator)$/;
    return
      if $LegalW[0] eq 'Menu' && &tree_get_sons($parent);
  }
  my $type=$LegalW[0];
  my $f=$db->Frame()->pack(-fill=>'both',-padx=>8,-pady=>18);
  my $reply;
  my $i=0;
  foreach my $lw (@LegalW)
  {
    $f->Radiobutton(-variable=>\$type,-value=>$lw,-text=>$lw)->
    grid(-row=>$i,-column=>0,-sticky=>'w',-padx=>18);
    $f->Label(-image=>$pic{lc($lw)})->
    grid(-row=>$i,-column=>1,-sticky=>'w',-padx=>18);
    $i++;
  }
  $db->resizable(1,0);
  &Coloring($db);
  $reply=$db->Show();
  return if $reply ne 'Ok';
  &do_insert($where,$type);
}

sub index_of
{
  my $id=shift;
  my $i=0;

  while ($tree[$i] !~ /(^|\.)$id$/) { $i++ };
  return $i;
}

sub do_insert
{
  my ($where,$type)=@_;
  # save current state for undo
  &undo_save();
  # 2. Find selected element index in @tree
  my $i=&index_of($selected);
  my $j=$i+1;
  $j=$i if $where eq 'before';
  if($where eq 'subwidget') # insert after last sub-entry
  {
    while($tree[$j] =~ /(^|\.)$selected(\.|$)/) { $j++ }
  }
  my $id=&generate_unique_id($type);
  # Ask user for human-readable name here:
  return unless ($id=&ask_new_id($id,$type));
  my $parent=&path_to_id($selected);
  $parent = $descriptor{$parent}->{'parent'}
    if($where ne 'subwidget');  # go up one level
  # 3. Create descriptor
  my ($insert_path)=grep(/(^|\.)$parent$/,@tree);
  $insert_path='mw' unless $insert_path;
  my @w_opt=(); 
  
  # default values:
  foreach my $k(keys %{$w_attr{$type}})
  {
    # text fields
    next if $k =~ 
      /^-(accelerator|show|command|createcmd|raisecmd|textvariable|variable|onvalue|offvalue)$/;
    push(@w_opt,"$k, $id") if($w_attr{$type}->{$k}=~/text/);
  }
  # relief for 'Label'
  push(@w_opt,'-relief, flat') 
    if $type =~ /^(Label|Menubutton|Checkbutton|Radiobutton|Scale|Message)$/;
  push(@w_opt,'-relief, sunken') 
    if $type =~ /^(BrowseEntry|Entry|Text|Listbox|LabEntry)$/;
  push(@w_opt,'-relief, ridge') 
    if $type =~ /^(LabFrame)$/;
  push(@w_opt,'-indicatoron, 1')
    if $type =~ /^(Radiobutton|Checkbutton)$/;

  my $geom='';
  if (&HaveGeometry($type))
  {
    # resolving geometry conflicts:
    # get geometry from 'brothers'
    my (@brothers)=&tree_get_sons($parent);
    ($geom)=$descriptor{$brothers[0]}->{'geom'};
    $geom='pack()' unless $geom; # default geometry if no 'brothers'
  }
  # Add data to internal structures according to gathered parameters:
  $descriptor{$id}=&descriptor_create($id,$parent,$type,join(', ',@w_opt),$geom);
    
  splice(@tree,$j,0,"${insert_path}.$id");

  # 4. Update display tree
  if($where eq 'subwidget')
  {
    $tf->add("${insert_path}.$id",-text=>$id,
      -data=>"${insert_path}.$id",-image=>$pic{lc($type)});
  }
  else
  {
    $tf->add("${insert_path}.$id",-text=>$id,-data=>"${insert_path}.$id",
      -image=>$pic{lc($type)},"-$where"=>$selected)
  }
  
  # For menu-related elements automatically create 'Menu':
  if($type =~ /^(Menubutton|cascade)$/)
  {
    $parent=$id;
    $id=&generate_unique_id('Menu');
    $descriptor{$id}=&descriptor_create($id,$parent,'Menu','','');
    splice(@tree,$j+1,0,"${insert_path}.$parent.$id");
    $tf->add("${insert_path}.$parent.$id",-text=>$id,
      -data=>"${insert_path}.$parent.$id",-image=>$pic{lc('Menu')});
  }
  &changes(1);
}

sub rename
{
  my $old_id=&path_to_id($selected);
  my $id=$old_id;
  return if $id eq 'mw';
  $id=&ask_new_id($id,$descriptor{$id}->{'type'});
  return unless $id;
  
  # save current state for undo
  &undo_save();
  # Read generated program and globally substitute $old_id with new one
  my (@program)=&code_print();
  map (s/\$($old_id)(\W)/\$$id$2/g,@program);
  &struct_new();
  &struct_read(@program);
  # &view_repaint;
  &changes(1);
}

sub ask_new_id
{
  my ($id,$type)=(@_);
  do
  {
    my $db=$mw->DialogBox(-title=>"Name for $type widget",-buttons=>['Proceed','Cancel']);
    $db->LabEntry(-textvariable=>\$id,-labelPack=>[-side=>'left',-anchor=>'w'],
      -label=>'Type UNIQUE and CORRECT name ')->pack(-pady=>20,-padx=>30);
    $db->resizable(1,0);
    &Coloring($db);
    return 0 if($db->Show() eq 'Cancel');
  }
  while(defined $descriptor{$id} || $id=~/\W/);
  return $id;
}

sub generate_unique_id
{
  my $type=shift;
  my $id;
  do
  {
    $obj_count++; $id = sprintf("w_${type}_%03.3d",$obj_count);
  }
  while(defined $descriptor{$id});

  return $id;
}

sub edit_properties
{
  return unless $selected;
re_enter:
  my $id=$selected; $id=~s/.*\.//;
  return unless defined $descriptor{$id};
  return if $id eq 'mw';
  return if $descriptor{$id}->{'type'} eq 'separator';
  my $pr=$w_attr{$descriptor{$id}->{'type'}};
  # return unless keys %$pr;
  
  my $d=$descriptor{$id};
  
  my @frm_pak=qw/-side left -fill both -expand 1 -padx 5 -pady 5/;
  my @pl=qw/-side left -padx 5 -pady 5/;
  
  my $db=$mw->DialogBox(-title=>"Properties of $id",-buttons=>['Accept','Cancel']);
  my $fbl=$db->LabFrame(-labelside=>'acrosstop',-label=>'Help')
    ->pack(-side=>'bottom',-anchor=>'s',-pady=>5);
  my $bl=$fbl->Label(-height=>6,-width=>80,-justify=>'left')->pack();
  
  my %val;
  my (%lpack)=();
  
  if (keys %$pr)
  {
    my $db_lf=$db->LabFrame(-labelside=>'acrosstop',-label=>"Widget ".$d->{'type'}." options:")
      ->pack(@frm_pak);
    my $db_lft = $db_lf->Scrolled('Tiler', -columns => 1, -scrollbars=>'oe')
      ->pack;
    (%val)=&split_opt($d->{'opt'});
    my @right_pack=(qw/-side right -padx 7/);
    foreach my $k(sort keys %$pr)
    {
      my $f = $db_lft->Frame(); $db_lft->Manage( $f );
      $f->Label(-text=>$k)->pack(-padx=>7,-pady=>10,-side=>'left');
      &cnf_dlg_ballon($bl,$f,$k);
      if($pr->{$k} eq 'color')
      {
        &ColorPicker($f,'Color',\$val{$k},1);
      }
      elsif($pr->{$k} eq 'float')
      {
        $f->Button(-text=>'+',-command=>sub{($val{$k})++})
          ->pack(@right_pack);
        $f->Entry(-textvariable=>\$val{$k},-width=>4)
          ->pack(-side=>'right');
        $f->Button(-text=>'-',-command=>sub{($val{$k})--;})
          ->pack(@right_pack);
      }
      elsif($pr->{$k} eq 'int+')
      {
	&NumEntry($f,-textvariable=>\$val{$k},
          -width=>4,-minvalue=>0)->pack(@right_pack);
      }
      elsif($pr->{$k} eq 'text')
      {
        if($d->{'type'} !~ /^(Frame|command|radiobutton|checkbutton|cascade)$/)
        {
          $val{$k}=$id if ! $val{$k} && $k !~
            /^-(accelerator|show|command|textvariable|variable|onvalue|offvalue)$/;
        }
        $f->Entry(-textvariable=>\$val{$k})->pack(@right_pack);
      }
      elsif($pr->{$k} eq 'callback')
      {
        $f->BrowseEntry(-variable=>\$val{$k},-width=>14,
          -choices=>\@callbacks)->pack(@right_pack);
      }
      elsif($pr->{$k} eq 'justify')
      {
        $val{$k}='left' unless $val{$k};
        my $mnb = $f->Menubutton(-underline=>0,-relief=>'raised',
          -textvariable=>\$val{$k}, -direction =>'below')->pack(@right_pack);
        my $mnu = $mnb->menu(qw/-tearoff 0/); $mnb->configure(-menu => $mnu);
        foreach my $r(qw/left center right/)
        {
          $mnu->command(-label=>$r,-image=>$pic{"justify_$r"},
            -command=>sub{$val{$k}=$r;});
        }
      }
      elsif($pr->{$k} eq 'relief')
      {
        $val{$k}='raised' unless $val{$k};
        my $mnb = $f->Menubutton(-underline=>0,-relief=>$val{$k},-borderwidth=>4,
          -textvariable=>\$val{$k}, -direction =>'below')->pack(@right_pack);
        my $mnu = $mnb->menu(qw/-tearoff 0/); $mnb->configure(-menu => $mnu);
        foreach my $r(qw/raised sunken flat ridge solid groove/)
        {
          $mnu->command(-label=>$r,-image=>$pic{"rel_$r"},
            -command=>sub{$val{$k}=$r;$mnb->configure(-relief=>$r)});
        }
      }
      elsif($pr->{$k} eq 'anchor')
      {
        &AnchorMenu($f,\$val{$k},'')->pack(@right_pack);
      }
      elsif($pr->{$k} eq 'side')
      {
        &SideMenu($f,\$val{$k},'')->pack(@right_pack);
      }
      elsif($pr->{$k} =~ /^menu\(/)
      {
        my $menu=$pr->{$k};
        $menu=~s/.*\(//;$menu=~s/\)//;
        if(split('\|',$menu)>2)
        {
          $f->Optionmenu(-options=>[split('\|',$menu)],-textvariable=>\$val{$k})
            ->pack(@right_pack);
        }
        else
        {
          my ($on,$off)=split('\|',$menu);
          $val{$k}=$on unless $val{$k};
          $f->Button(-textvariable=>\$val{$k},-relief=>'flat',
            -command=>sub{$val{$k}=($val{$k} eq $on)?$off:$on;})->pack(@right_pack);
        }
      }
      elsif($pr->{$k} eq 'lpack')
      {
        $val{$k}=~s/[\[\]']//g;
        (%lpack)=&split_opt($val{$k});
        $f->Optionmenu(-options=>[qw/n ne e se s sw w nw/],
          -textvariable=>\$lpack{'-anchor'})->pack(@right_pack);
        $f->Optionmenu(-options=>[qw/left top right bottom/],
          -textvariable=>\$lpack{'-side'})->pack(@right_pack);
      }
    }
    foreach (0 .. 9-scalar(keys %$pr))
    {
      $db_lft->Manage( $db_lft->Frame() );
    }
  }
  my ($geom_type,$geom_opt,$n);
  my (%g_val);
  my (@brothers);
  # geometry part
  if ($d->{'geom'})
  {
    my $db_rf=$db->LabFrame(-labelside=>'acrosstop',-label=>'Widget geometry:')
      ->pack(@frm_pak); # define right frame
    ($geom_type,$geom_opt)=split('[)(]',$d->{'geom'}); # get type and options
    (%g_val)=&split_opt($geom_opt); # get geometry option values
    $n = $db_rf->NoteBook( -ipadx => 6, -ipady => 6 )
      ->pack(qw/-expand yes -fill both -padx 5 -pady 5 -side top/);

    my $g_pack = $n->add('pack', -label => 'pack', -underline => 0);
    my $g_grid = $n->add('grid', -label => 'grid', -underline => 0);
    my $g_place = $n->add('place', -label => 'place', -underline => 1);

    # pack options:
    {
      &cnf_dlg_ballon($bl,$g_pack->Label(-text=>'-side',-justify=>'left')->
        grid(-row=>0,-column=>0,-sticky=>'w',-padx=>8),'-side');
      &SideMenu($g_pack,\$g_val{'-side'},$bl)->grid(-row=>0,-column=>1,-pady=>4);
    }
    {
      &cnf_dlg_ballon($bl,$g_pack->Label(-text=>'-anchor',-justify=>'left')->
        grid(-row=>1,-column=>0,-sticky=>'w',-padx=>8),'-anchor');
      &AnchorMenu($g_pack,\$g_val{'-anchor'},$bl)->grid(-row=>1,-column=>1,-pady=>4);
    }
    {
      &cnf_dlg_ballon($bl,$g_pack->Label(-text=>'-fill',-justify=>'left')->
        grid(-row=>2,-column=>0,-sticky=>'w',-padx=>8),'-fill');
      my $mnb = $g_pack->Menubutton(-direction=>'below')->grid(-row=>2,-column=>1,-pady=>4);
      &cnf_dlg_ballon($bl,$mnb,'-fill');
      my $mnu = $mnb->menu(qw/-tearoff 0/); $mnb->configure(-menu => $mnu);
      foreach my $r('','x','y','both')
      {
        $mnu->command(-label=>$r,-image=>map_pic('fill',$r),-columnbreak=>($r eq 'x'),
          -command=>sub{$g_val{'-fill'}=$r;$mnb->configure(-image=>map_pic('fill',$r))});
        $mnb->configure(-image=>map_pic('fill',$r)) if($r eq $g_val{'-fill'});
      }
    }
    {
      &cnf_dlg_ballon($bl,$g_pack->Label(-text=>'-expand',-justify=>'left')->
        grid(-row=>3,-column=>0,-sticky=>'w',-padx=>8),'-expand');
      &cnf_dlg_ballon($bl,$g_pack->
        Button(-textvariable=>\$g_val{'-expand'},-relief=>'flat',-command=>
	 sub{$g_val{'-expand'}=1-$g_val{'-expand'}})->grid(-row=>3,-column=>1,-pady=>4),'-expand');
	
    }
    my $i=0;
    foreach my $k(qw/-ipadx -ipady -padx -pady/)
    {
      $i++;
      &cnf_dlg_ballon($bl,$g_pack->Label(-text=>$k,-justify=>'left')->
        grid(-row=>3+$i,-column=>0,-sticky=>'w',-padx=>8),$k);
      my $f=$g_pack->Frame()->grid(-row=>3+$i,-column=>1,-pady=>4);
      &cnf_dlg_ballon($bl,$f,$k);
      &NumEntry($f,-textvariable=>\$g_val{$k},-width=>4,
        -minvalue=>0)->pack(-side=>'right');
    }
  
    # geometry: grid
    {
      &cnf_dlg_ballon($bl,$g_grid->Label(-text=>'-sticky',-justify=>'left')->
        grid(-row=>0,-column=>0,-sticky=>'w',-padx=>8),'-sticky');
      my $f=$g_grid->Frame()->grid(-row=>0,-column=>1,-pady=>4);
      &cnf_dlg_ballon($bl,$f,'-sticky');
      my %st;
      foreach my $s (qw/n s e w/)
      {
        $st{$s}=grep(/$s/,$g_val{'-sticky'});
        $f->Checkbutton(-text=>$s,-variable=>\$st{$s},
          -command => sub{$g_val{'-sticky'}=~s/$s//g;$g_val{'-sticky'}.=$s if $st{$s}})
          ->pack(-side=>'left');
      }
    }
    my $i=1;
    foreach my $k(qw/-column -row -columnspan -rowspan -ipadx -ipady -padx -pady/)
    {
      &cnf_dlg_ballon($bl,$g_grid->Label(-text=>$k,-justify=>'left')->
        grid(-row=>$i,-column=>0,-sticky=>'w',-padx=>8),$k);
      my $f=$g_grid->Frame()->grid(-row=>$i,-column=>1,-pady=>4);
      &cnf_dlg_ballon($bl,$f,$k);
      &NumEntry($f,-textvariable=>\$g_val{$k},-width=>4,
        -minvalue=>($k=~/(-column|-row)$/)?0:1)->pack(-side=>'right');
      $i++;
    }

    # geometry: place
    my $i=0;
    foreach my $k(qw/-height -width -x -y -relheight -relwidth -relx -rely/)
    {
      &cnf_dlg_ballon($bl,$g_place->Label(-text=>$k,-justify=>'left')->
        grid(-row=>$i,-column=>0,-sticky=>'w',-padx=>8),$k);
      my $f=$g_place->Frame()->grid(-row=>$i,-column=>1,-pady=>4);
      &cnf_dlg_ballon($bl,$f,$k);
      &NumEntry($f,-textvariable=>\$g_val{$k},-width=>4,
        -minvalue=>0)->pack(-side=>'right');
      $i++;
    }
  
    $n->raise($geom_type);

  }
  # bind baloon message + help on click
  $bl->bind('<Enter>',
    sub{$bl->configure(-text=>"Click here to get help about current widget\n".
      "by TkPOD utility.\n\n".
      ($n?"Right-click here for current geometry manager help":''))});
  $bl->bind('<Leave>',
    sub{$bl->configure(-text=>'')});
  $bl->bind('<1>',[\&tkpod,$id]);
  $bl->bind('<3>',sub{&tkpod($n->raised())}) if $n;
  $db->resizable(0,0);
  &Coloring($db);
  my $reply=$db->Show();
  return if($reply eq 'Cancel');
  if (keys %$pr)
  {
    $val{'-labelPack'}="[-side=>'$lpack{'-side'}',-anchor=>'$lpack{'-anchor'}']"
      if %lpack;
  }
  if ($d->{'geom'})
  {
    $geom_type=$n->raised();
    # check for geometry conflicts here:
    # find all 'brothers' for current widget
    (@brothers)=grep($descriptor{$_}->{'type'} ne 'packAdjust',&tree_get_brothers($id));
    # get their geometry
    map ( $_=$descriptor{$_}->{'geom'} ,@brothers);
    # if any of brothers does not match:
    # Ask user about possible conflict solution
    # 'Propagate' | 'Adopt' | 'Back' | 'Cancel'
    # go to start on 'Back'
    # return on 'Cancel'
    # otherwise - fix geometry respectively after 'undo_save'
    if (grep(!/^$geom_type/,@brothers))
    {
      # we have conflict with one of the brothers
      my $eb = $mw->DialogBox(-title=>'Geometry conflict!',
        -buttons=>[qw/Propagate Adopt Back Cancel/]);
      $eb->Label(-justify=>'left',
        -text=>"Geometry <$geom_type> for widget $id conflicts with\n".
        "other sub-widgets of ".$descriptor{$id}->{'parent'}." :\n".
        join(' ',grep(!/^$geom_type/,@brothers)).
        "\n\n   Now you can:\n".
        " Propagate this geometry to neighbor widgets\n".
        " Adopt current widget geometry to it's neighbors\n".
        " return Back to properties window\n".
        " or Cancel your changes and exit properties window")->pack();
      $eb->resizable(1,0);
      &Coloring($eb);
      $reply = $eb->Show();
      return if $reply eq 'Cancel';
      goto re_enter if $reply eq 'Back';
    }
  } 
  # save current state for undo
  &undo_save();
  if (keys %$pr)
  {
    foreach my $k( keys %val)
    {
      $val{$k} =~ tr/,/./ unless $k eq '-labelPack';
      if($k =~/^-(showvalue|tearoff|indicatoron|underline)$/)
      {
        delete $val{$k} if $val{$k}=~/^\s*$/;
      }
      else
      {
        delete $val{$k} unless $val{$k};
      }
      # if callback - try to store in @callbacks array
      if($pr->{$k} eq 'callback')
      {
        &PushCallback($val{$k});
      }
    }
    $d->{'opt'}=join(', ',%val);
  }
  if ($d->{'geom'})
  {
    foreach my $k(keys %g_val)
    {
      if($k =~/^(-row|-column)$/)
      {
        delete $g_val{$k} if $g_val{$k}=~/^\s*$/;
      }
      else
      {
        delete $g_val{$k} unless $g_val{$k};
      }
      delete $g_val{$k} unless grep($k eq $_,@{$w_geom{$geom_type}})
    }
    $geom_opt=join(',',%g_val);
    $d->{'geom'}=$geom_type."($geom_opt)";
    if ($reply eq 'Propagate')
    {
      (@brothers)=&tree_get_brothers($id);
      foreach (@brothers) { $descriptor{$_}->{'geom'}=$d->{'geom'} }
    }
    if ($reply eq 'Adopt')
    {
      $d->{'geom'} = $descriptor{(&tree_get_brothers($id))[0]}->{'geom'}
    }
  }
  &changes(1);
}

sub PushCallback
{
  my (@arg)=@_;
  foreach my $arg (@arg)
  {
    next unless $arg;
    $arg="\\\&$arg" if $arg=~/^\w/ && $arg!~/^(sub[\s\{]|\[)/;
    push(@callbacks,$arg)
      unless grep($arg eq $_, @callbacks);
  }
}

sub tkpod
{
  my $id=shift;
  $id=shift if ref $id; # for callbacks with editor widget refs
  $id=$selected unless $id; # default if no argument
  $id=~s/.*\.//; # clean up when 'selected' used
  my $widget='';
  $widget=$descriptor{$id}->{'type'} # for real widgets!
    if $descriptor{$id}->{'type'} =~ /^[A-Z]/;
  $widget='Adjuster' if $descriptor{$id}->{'type'} eq 'packAdjust';
  $widget='NoteBook' if $descriptor{$id}->{'type'} eq 'NoteBookFrame';
  $widget=$id if $id=~
    /^(grid|place|pack|overview|options|option|tkvars|grab|bind|bindtags|callbacks|event)$/;
  $widget='MainWindow' if $id eq 'mw';
  $widget='Menu' unless $widget;
  $mw->Busy;
  my $pod_util = ($os eq 'win')?
    'start cmd /c perldoc' :
    'xterm -e perldoc';
  system("$pod_util Tk::".$widget.' &');
  $mw->Unbusy;
}

sub SideMenu
{
  my ($where,$pvar,$balloon)=(@_);
  my $mnb = $where->Menubutton(-direction=>'below',-cursor=>'left_ptr');
  &cnf_dlg_ballon($balloon,$mnb,'-side')
   if $balloon;
  my $mnu = $mnb->menu(qw/-tearoff 0/); $mnb->configure(-menu => $mnu);
  foreach my $r('','left','bottom','top','right')
  {
    my $break=0;
    $break=1 if $r =~ /left|top/;
    $mnu->command(-label=>$r,-image=>map_pic('side',$r),-columnbreak=>$break,
      -command=>sub{$$pvar=$r;$mnb->configure(-image=>map_pic('side',$r))});
    $mnb->configure(-image=>&map_pic('side',$r)) if($r eq $$pvar);
  }
  return $mnb;
  # end SideMenu
}

sub AnchorMenu
{
  my ($where,$pvar,$balloon)=(@_);
  my $mnb = $where->Menubutton(-direction=>'below',-cursor=>'left_ptr');
  &cnf_dlg_ballon($balloon,$mnb,'-anchor') 
   if $balloon;
  my $mnu = $mnb->menu(qw/-tearoff 0/); $mnb->configure(-menu => $mnu);
  foreach my $r('','nw','w','sw','n','center','s','ne','e','se')
  {
    my $break=0;
    $break=1 if $r =~ /^n/; # break before North pole ;-)
    $mnu->command(-label=>$r,-image=>&map_pic('anchor',$r),-columnbreak=>$break,
      -command=>sub{$$pvar=$r;$mnb->configure(-image=>&map_pic('anchor',$r))});
    $mnb->configure(-image=>&map_pic('anchor',$r)) if($r eq $$pvar);
  }
  return $mnb;
}

# Structures hadling:
sub path_to_id
{
  return (split /\./,shift)[-1];
}

sub tree_get_sons
{
  my $parent=shift;
  my @sons;
  
  foreach my $widget(grep (/(^|\.)$parent\.[^\.]+$/,@tree))
  {
    my $wid=$widget;
    $wid =~ s/.*\.//;
    push(@sons,$wid);
  }
  return @sons;
}

sub tree_get_brothers
{
  my ($id)=(@_);
  my ($parent)=$descriptor{$id}->{'parent'};
  return grep(!/^$id$/,&tree_get_sons($parent));
}

sub cnf_dlg_ballon
{
  my ($bln,$w,$key)=(@_);
  return unless defined $cnf_dlg_ballon{$key};
  $w->bind("<Enter>",sub{$bln->configure(-text=>$cnf_dlg_ballon{$key})});
  $w->bind("<Leave>",sub{$bln->configure(-text=>'')});
}

sub map_pic
{
  my ($name,$x)=@_;
  my $p="${name}_$x"; 
  return $pic{'undef'} unless defined $pic{$p};
  return $pic{$p};
}

############################################################
#                   Undo/Redo section
############################################################
sub undo_save
{
  @redo=(); push(@undo,join("\n",&code_print()));
}

sub redo
{
  return unless @redo;
  my $sel_save=$selected;
  push(@undo,join("\n",&code_print())); # undo <= current
  &struct_new();
  &struct_read(split("\n",pop(@redo)));
  &view_repaint;
  $sel_save='mw' unless defined $widgets{$sel_save};
  &set_selected($sel_save);
}

sub undo
{
  return unless @undo;
  my $sel_save=$selected;
  # clear current design and restore from backup:
  push(@redo,join("\n",&code_print())); # redo <= current
  &struct_new();
  &struct_read(split("\n",pop(@undo)));
  &view_repaint;
  $sel_save='mw' unless defined $widgets{$sel_save};
  &set_selected($sel_save);
}

###############################################
#        Generated code handling section
###############################################

sub code_print
{
  my @code=();
  foreach my $element(@tree)
  {
    my $code=&code_line_print($element);
    next unless $code;
    push (@code,$code);
  }
  return @code;
}

sub code_line_print
{
  my $code;
  my $id=&path_to_id(shift);
  
  return '' unless defined $descriptor{$id};
  return '' if $id eq 'mw';
  my $d=$descriptor{$id};
  my $my='';
  $my = 'my ' if ($file_opt{'strict'});
  my $postconfig='';
  $postconfig=' $'.$d->{'parent'}."->configure(-menu=>\$$id);"
    if $d->{'type'} eq 'Menu';
  my $geom = ' -> '.&quotate($d->{'geom'});
  $geom='' unless &HaveGeometry($d->{'type'});
  my $parent=$d->{'parent'};
  $parent = $descriptor{$d->{'parent'}}->{'parent'}
    if $descriptor{$parent}->{'type'} eq 'cascade';
  my $type=$d->{'type'};
  my $opt=&quotate($d->{'opt'});
  if($descriptor{$parent}->{'type'} eq 'NoteBook')
  {
    $type='add';
    $opt="'$id', $opt";
  }
  $code =
    $my.'$'.$d->{'id'}.' = $'.$parent.' -> '.
    $type.' ( '.$opt.' )'.
    $geom.';'.$postconfig;
  return $code;
}

sub quotate
{
  my ($opt_list)=shift;
  my ($prefix,$suffix)=($opt_list=~/^\s*([^\(]*\().*(\)[^\)]*)/);
  $opt_list =~ s/^\s*([^\(]*\()//; $opt_list =~ s/(\)[^\)]*)//;
  my (%opt)=&split_opt($opt_list);
  foreach my $k(keys %opt)
  {
    $opt{$k} = "'$opt{$k}'" 
      unless $opt{$k} =~ /^(\d|\[)/ || $k =~ /(variable|command|cmd)$/;
    if($opt{$k} =~ /^\[/ && $opt{$k} !~ /'/)
    {
      $opt{$k} =~ s/[\[\]]//g;
      my (%labelPack)=&split_opt($opt{$k});
      foreach (keys %labelPack)
      {
        $labelPack{$_}="'$labelPack{$_}'" unless $labelPack{$_}=~/^[\@\$\\]/
      }
      $opt{$k} = '['.join(',',map{"$_=>$labelPack{$_}"} keys %labelPack).']'
    }
  }
  return $prefix. join(', ',map{"$_=>$opt{$_}"} keys %opt) . $suffix;
}

# Global structures used:
# -----------------------
# %descriptor (id->descriptor)
# @tree
# @user_auto_vars - user-defined variables to be pre-declared automatically
# use vars qw/$x/;
#
# Global widgets used:
# --------------------
# $tf - list of objects in tree form
#
sub struct_read # read external data structure to internal
{
  my (@lines)=@_;
  my @ERRORS;

  my $count=0; # just for diagnostics - input line number
  my $user_subroutines=0;
  chomp @lines;
  # for each widget description line:
  # 1. get Id, Parent, Type, parameters, geometry
  # 2. check for Parent existance
  # 3. add line to tree descriptor
  # 4. add element to widget descriptor
  # 5. add element to id->descriptor hash
  foreach my $line( @lines )
  {
    $count++;
    if($line=~/^#===vptk end===/ ||
      $user_subroutines)
    {
      push(@user_subroutines,$line);
      &PushCallback($line=~/sub\s+([^\s\{]+)/);
      $user_subroutines=1;
      next;
    }
    if($line=~/^\s*#[^!]/)
    {
      $line =~ s/^\s*#\s*//;
      $file_opt{'description'} .= $line;
      $file_opt{'fullcode'}=1;
    }
    if($line=~/^\s*my\s+/)
    {
      $line=~s/^\s*my\s+//;
      $file_opt{'strict'}=1;
    }
    if($line=~/-title\s*=>\s*'/)
    {
      ($file_opt{'title'}) = $line=~/-title\s*=>\s*'([^']*)'/;
      $file_opt{'fullcode'}=1;
      next;
    }
    next if $line=~/^\s*[^\$]/;
    next if $line=~/^\s*\$mw\s*=/;
    $line =~ s/'//g; # ignore self-generated quotes
    if($line =~ /^\s*\$/)
    {
      my ($id,$parent,$type,$opt,$geom);
      ($id,$parent,$type,$opt,$geom) =
        $line =~ /^\s*\$(\S+)\s+=\s+\$(\S+)\s+->\s+([^(]+)\(([^)]+)\)\s+->\s+([^;]+);/;
      unless($id)
      {
        my $virtual_parent;
        ($id,$virtual_parent,$type,$opt,$parent) =
          $line =~ /^\s*\$(\S+)\s+=\s+\$(\S+)\s+->\s+([^(]+)\(([^)]+)\); \$(\S+)->configure\(-menu=>.*\);/;
      }
      unless($id)
      {
        ($id,$parent,$type,$opt) =
          $line =~ /^\s*\$(\S+)\s+=\s+\$(\S+)\s+->\s+([^(]+)\(([^)]+)\);\s*$/;
      }
      # 2.
      next unless $id;
      if($parent ne 'mw' && ! defined $descriptor{$parent})
      {
        # error - report in Tk style:
	push @ERRORS, "line ${count}: Wrong parent id <$parent> for widget <$id>";
	next;
      }
      if(defined $descriptor{$id})
      {
        push @ERRORS, "line ${count}: Duplicated widget <$id> definition\n";
	next;
      }
      $obj_count++;
      my ($parent_path)=grep(/$parent$/,@tree);
      $parent_path='mw' unless $parent_path;
      my ($insert_path)=(grep(/$parent\.[^.]+$/,@tree))[-1];
      push(@tree,"$parent_path.$id");
      $type=~s/\s//g;
      if ($type eq 'add')
      {
        $type='NoteBookFrame';
        $opt=~s/^\s*\S+\s*,\s*//;
      }
      if($insert_path)
      {
        $tf->add("$parent_path.$id",-text=>$id,-data=> "$parent_path.$id",
          -image=>$pic{lc($type)},-after=>$insert_path);
      }
      else
      {
        $tf->add("$parent_path.$id",-text=>$id,-data=> "$parent_path.$id",-image=>$pic{lc($type)});
      }
      $descriptor{$id}=&descriptor_create($id,$parent,$type,$opt,$geom);
      if($opt=~/variable/)
      {
        # store user-defined variable in array
	my ($user_var)=($opt=~/\\\$(\w+)/);
	push(@user_auto_vars,$user_var)
	  if $user_var && ! grep($_ eq $user_var,@user_auto_vars);
      }
      &PushCallback($opt=~/(?:-command|-\wcmd)\s*=>\s*([^,]+), /g);
    }
  }
  if(@ERRORS)
  {
    if(@ERRORS > 10)
    {
      splice(@ERRORS,10);
      push @ERRORS, "Too many errors - skipped\n";
    }
    &ShowDialog(-title=>"Errors:",-text=>join("\n",@ERRORS));
  }
}

sub descriptor_create
{
  my @p=@_;
  map s/\s*$//,@p;
  map s/^\s*//,@p;
  my ($id,$parent,$type,$opt,$geom)=@p;

  my $descriptor={'id'=>$id,'parent'=>$parent,'type'=>$type,'opt'=>$opt,'geom'=>$geom};
  $descriptor{$id}=$descriptor;
  return $descriptor;
}

sub split_opt
{
  # input: options string
  # otput: array of pairs (-param=>value,-param2=>value2,...)
  my $opt=shift || return;
  my %result;
  my @virtual_arrays;

  # if options contain 'reference to anonimous array' it must be temporary 
  # replaced with real array reference
  while($opt =~ /\[[^\[\]]+\]/)
  {
    push(@virtual_arrays,($opt =~ /(\[[^\[\]]+\])/));
    $opt=~s/\[[^\[\]]+\]/ARRAY($#virtual_arrays)/;
  }

  (%result)=split(/\s*(?:,|=>)\s*/,$opt);
  foreach (keys %result)
  {
    $result{$_}=~s/ARRAY\((\d+)\)/$virtual_arrays[$1]/;
  }
  return (%result);
}

sub callback
{
  my $reply=&ShowDialog(-bitmap=>'info',-title=>'Callback triggered:',
    -text=> "This action triggered callback function <$_[0]>",
    -buttons=>['Close','Edit callbacks','Widget properties','Help']);
  &file_properties if($reply eq 'Edit callbacks');
  &edit_properties if($reply eq 'Widget properties');
  &tkpod('callbacks') if($reply eq 'Help');
}

__END__
