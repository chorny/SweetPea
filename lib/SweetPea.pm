package SweetPea;

BEGIN {
    use Exporter();
    use vars qw( @ISA @EXPORT @EXPORT_OK );
    @ISA    = qw( Exporter );
    @EXPORT = qw(makeapp);
}

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use CGI::Cookie;
use CGI::Session;
use FindBin;
use File::Find;

=head1 NAME

SweetPea - A simple light-weight web application framework based on an MVC design pattern using only CGI!

=head1 VERSION

Version 2.06

=cut

our $VERSION = '2.06';

=head1 SYNOPSIS

SweetPea is designed primarily as a KISS (keep it simple stupid) web framework. SweetPea was
designed using some of my favorite functions from Mojo and Catalyst. The need for SweetPea arose
after performing a contrast and comparison between various web frameworks, specifically focusing
on the CPAN modules available to Perl developers. SweetPea is a web framework that requires little
to no configuration (PnP) but handles all the standard web application facilities as well as an MVC
design pattern. So heres my take on an easy-to-use web framework.

using SweetPea is as easy as ...

    ... from the cli (command line interface)
    
    perl -MSweetPea -e makeapp
    
    Created file /sweet/App.pm (chmod 755) ...
    Created file /.pl (chmod 755) ...
    Created file /.htaccess (chmod 755) ...
    Created file /sweet/application/Controller/Root.pm (chmod 754) ...
    Created file /sweet/application/Model/Schema.pm (chmod 754) ...
    Created file /sweet/application/View/Main.pm (chmod 754) ...
    Created file /sweet/application/Controller/Sweet.pm (chmod 754) ...

    ... in the .pl script file generated by the makeapp method (http://localhost/.pl/sweet/welcome) which is
    masked by the an htaccess file if using apache (enables pretty-urls) e.g.
    (http://localhost/sweet/welcome).
    
    use SweetPea;
    my $s = SweetPea->new->run;
    
    # Note! The url pattern is /:controller/:action so http://localhost/sweet/welcome execute the code found in
    sweet/application/Controller/Sweet.pm - sub welcome { ... }. Also note that multi-level namespaces are supported, e.g.
    http://localhost/admin/users/account/profile will match either Controller::Admin::Users::Account::Profile::_index() or
    Controller::Admin::Users::Account::profile() or else default to Controller::Root::_index()
    
    # Note! sweet/application/Controller/Root.pm should exist as Controller::Root::_index() is where failed requests
    are routed to by default. If that module and routine doesn't exist a blank page will be rendered on failure. It is
    recommended to use Root::_index() as your website/application landing page.

=head1 EXPORT

    makeapp (application generation)

=head1 METHODS
=cut

=head2 new

The new method initializes a new SweetPea object.

=cut

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    #declare config stuff
    $self->{store}->{application}->{html_content} = [];
    $self->{store}->{application}->{content_type} = 'text/html';
    $self->{store}->{application}->{path}         = $FindBin::Bin;
    return $self;
}

=head2 run

The run method, well, does what it says, it initializes and runs the application.

=cut

sub run {
    my $self = shift;
    $self->_plugins;
    $self->_self_check;
    $self->_init_dispatcher;
}

=begin ignore 

The plugins method is an internal method (not to be called externally) that sets
up module accessors.

=end ignore
=cut

sub _plugins {
    my $self = shift;

    # NOTE! The database and email plugins are not used internally so changing
    # them to a module of you choice won't effect any core functionality. Those
    # modules/plugins should be configured in App.pm.
    # load modules using the following procedure, they will be available to the
    # application as $s->nameofobject.

    $self->plug(
        'cgi',
        sub {
            my $self = shift;
            return CGI->new;
        }
    );

    $self->plug(
        'cookie',
        sub {
            my $self = shift;
            push @{ $self->{store}->{application}->{cookie_data} },
              new CGI::Cookie(@_);
            return $self->{store}->{application}->{cookie_data}
              ->[ @{ $self->{store}->{application}->{cookie_data} } ];
        }
    );

    eval 'use CGI::Session';
    warn 'It looks like you don\'t have CGI::Session installed.' if $@;
    unless ($@) {
        $self->plug(
            'session',
            sub {
                my $self = shift;
                my $cgis = CGI::Session->new(
                    "driver:file",
                    undef,
                    {
                        Directory => $self->application->{path}
                          . '/sweet/sessions'
                    }
                );
                $cgis->name("SID");
                return $cgis;
            }
        );
    }

    # load non-core plugins from App.pm
    App->plugins($self);

    return $self;
}

=begin ignore

The _load_path_and_actions method is an internal method that scans the controller folder and creates a list of
controllers and methods for routing, forwarding, detaching and otherwise loading methods dynamically.

=end ignore
=cut

sub _load_path_and_actions {
    my $self = shift;

    if ( !$self->application->{actions} ) {
        my $actions = {};
        find( \&_load_path_actions,
            $self->application->{path} . '/sweet/application/Controller' );

        sub _load_path_actions {
            no warnings 'redefine';
            no strict 'refs';
            my $name  = $File::Find::name;
            my $magic = '';
            my @dir   = ();
            if ( $name =~ /.pm$/ ) {
                require $name;
                my $controller = $name;
                $controller =~ s/\\/\//g;    # convert non-unix paths
                $controller =~ s/.*Controller\/(.*)\.pm$/$1/;
                my $controller_ref = $controller;
                $controller_ref =~ s/\//\:\:/g;
                @dir = split /\//, $controller;
                open( INPUT, "<", $name )
                  or die "Couldn't open $name for reading: $!\n";
                my @code = <INPUT>;
                my @routines = grep { /^sub\s?(.*)[\s\n]{0,}?\{/ } @code;
                $_ =~ s/sub//g foreach @routines;
                $_ =~ s/[^a-zA-Z0-9\_\-]//g foreach @routines;

                # dynamically create new (initialization routine)
                my $new = "Controller::" . $controller_ref . "::_new"
                  if $controller_ref;
                *{$new} = sub {
                    my $class = shift;
                    my $self  = {};
                    bless $self, $class;
                    return $self;
                  }
                  if $new;

                foreach (@routines) {

                    # dynamically create method references
                    my $code =
                        '$actions->{lc("/$controller/$_")} = '
                      . 'sub{ my ($s, $class) = @_; if ($class) { return $class->'
                      . $_
                      . '($s) } else { $class = Controller::'
                      . $controller_ref
                      . '->_new; return $class->'
                      . $_
                      . '($s); } }';
                    eval $code;
                }
                close(INPUT);
            }
        }
        $self->application->{actions} = $actions;
    }
    return $self->application->{actions};
}

=begin ignore

This _self_check method is an internal method that verifies that all the required
elements are in place to ensure a happy execution.

=end ignore
=cut

sub _self_check {
    my $self = shift;

    # check manifest if available
    my $path = $self->application->{path};
    return $self;
}

=begin ignore

The _init_dispatcher method is an internal method that loads all the applications
methods and determines which methods to use.

=end ignore
=cut

sub _init_dispatcher {
    my $self = shift;

    my %dispatch = %{ $self->_load_path_and_actions() };
    my $path     = $self->cgi->path_info();
    $path =~ s/^\/\.pl//;
    $path =~ s/\/$//;
    my $handler = $dispatch{$path};

    #set uri vars
    my $bse_path = $ENV{SCRIPT_NAME};
    my $cur_path = $self->cgi->url();
    my ( @links, $controller, $action );

    $bse_path =~
      s/\.pl$//;    # gets the path to root (where the .pl file is located)
    $cur_path =~ s/.*$bse_path//;
    $cur_path = $bse_path . $cur_path;

    # get controller and action segments
    if ( ref($handler) eq "CODE" ) {
        @links      = split /\//, $path;    # :)
        $action     = pop @links;
        $controller = join '/', @links;
    }
    else {
        $controller = $path;
    }

    $self->application->{'url'}->{root}       = $bse_path;
    $self->application->{'url'}->{here}       = $cur_path;
    $self->application->{'url'}->{path}       = $path;
    $self->application->{'url'}->{controller} = $controller;
    $self->application->{'url'}->{action}     = $action;

    # restrict access to hidden methods (methodsprefixed with an underscore)
    if ( $path =~ /.*\/_.*$/ ) {
        print $self->cgi->header, $self->cgi->start_html('Not found'),
          $self->cgi->h1('Access Denied'), $self->cgi->end_html;
        exit;
    }

    # set default action if action not defined
    unless ( exists $dispatch{$path} ) {
        $handler = $dispatch{"$controller/_index"}
          if exists $dispatch{"$controller/_index"};
        $handler = $dispatch{"/root/_index"}
          if exists $dispatch{"/root/_index"}
              && !$dispatch{"$controller/_index"};
    }

    if ( ref($handler) eq "CODE" ) {

        #run user-defined begin routine or default to root begin
        $dispatch{"$controller/_begin"}->($self)
          if exists $dispatch{"$controller/_begin"};
        $dispatch{"/root/_begin"}->($self)
          if exists $dispatch{"/root/_begin"}
              && !$dispatch{"$controller/_begin"};

        #run user-defined response routines
        $handler->($self);

        #run user-defined end routine or default to root end
        $dispatch{"$controller/_end"}->($self)
          if exists $dispatch{"$controller/_end"};
        $dispatch{"/root/_end"}->($self)
          if exists $dispatch{"/root/_end"} && !$dispatch{"$controller/_end"};

        #run pre-defined response routines
        $self->start();

        #run finalization and cleanup routines
        $self->finish();
    }
    else {

        # print http header
        print $self->cgi->header, $self->cgi->start_html('Not found'),
          $self->cgi->h1('Not found'), $self->cgi->end_html;
        exit;
    }
}

=head2 start

The start method should probably be named (startup) because it is the method
which configures the environment and performs various startup tasks.

=cut

sub start {
    my $self = shift;

    # handle session
    if ( defined $self->{'.session'} ) {
        $self->session->expire();
        $self->cookie(
            -name  => $self->session->name,
            -value => $self->session->id
        );
    }

    print $self->cgi->header(
        -type   => $self->application->{content_type},
        -status => 200,
        -cookie => $self->cookies
    );
}

=head2 finish

The finish method performs various cleanup tasks after the request reaches its end.

=cut

sub finish {
    my $self = shift;

    # print gathered html
    foreach ( @{ $self->html } ) {
        print "$_\n";
    }

    # commit session changes if a session has been created
    $self->session->flush() if defined $self->{'.session'};
}

=head2 forward

The forward method executes a method from within another class, then continues
to execute instructions in the method it was called from.

=cut

sub forward {
    my ( $self, $path, $class ) = @_;

    #get actions
    my %dispatch = %{ $self->_load_path_and_actions() };

    #run requested routines
    $dispatch{"$path/_begin"}->( $self, $class )
      if exists $dispatch{"$path/_begin"};
    $dispatch{"$path"}->( $self, $class ) if exists $dispatch{"$path"};
    $dispatch{"$path/_end"}->( $self, $class )
      if exists $dispatch{"$path/_end"};
}

=head2 detach

The detach method executes a method from within another class, then immediately
executes the special "end" method which finalizes the request.

=cut

sub detach {
    my ( $self, $path, $class ) = @_;
    $self->forward( $path, $class );
    $self->finish();
}

=head2 store

The store method is in accessor to the special "store" hashref.

=cut

sub store {
    my $self = shift;
    return $self->{store};
}

=head2 application

The application method is in accessor to the special "application" hashref.

=cut

sub application {
    my $self = shift;
    return $self->{store}->{application};
}

=head2 contenttype

The contenttype method set the desired output format for use with http headers

=cut

sub contenttype {
    my ( $self, $type ) = @_;
    $self->application->{content_type} = $type;
}

=head2 controller

The action method returns the current requested MVC controller/package

=cut

sub controller {
    my $self = shift;
    return $self->uri->{controller};
}

=head2 action

The action method returns the current requested MVC action

=cut

sub action {
    my $self = shift;
    return $self->uri->{action};
}

=head2 url/uri

The url/uri methods returns a completed uri string or reference to root, here or path
variables, e.g. $s->uri->{here}.

=cut

sub uri {
    my ( $self, $path ) = @_;
    return $self->{store}->{application}->{'url'} unless $path;
    return
        $self->cgi->url( -base => 1 )
      . $self->{store}->{application}->{'url'}->{'root'}
      . $path;
}   sub url { return shift->uri(@_); }

=head2 path

The path method returns a completed path to root or location passed to the path method.

=cut

sub path {
    my ( $self, $path ) = @_;
    return $path ? $self->{store}->{application}->{'path'} :
    $self->{store}->{application}->{'path'} . $path;
}

=head2 cookies

Returns a list of cookies set throughout the duration of the request.

=cut

sub cookies {
    my $self = shift;
    return
      ref $self->{store}->{application}->{cookie_data} eq "ARRAY"
      ? @{ $self->{store}->{application}->{cookie_data} }
      : ();
}

=head2 html

The html method sets data to be output to the browser or if called with no
parameters returns the data recorded and clears the data store.

=cut

sub html {
    my ( $self, @html ) = @_;
    if (@html) {
        my @existing_html =
          $self->{store}->{application}->{html_content}
          ? @{ $self->{store}->{application}->{html_content} }
          : ();
        push @existing_html, @html;
        $self->{store}->{application}->{html_content} = \@existing_html;
        return;
    }
    else {
        if ( $self->{store}->{application}->{html_content} ) {
            my @content = @{ $self->{store}->{application}->{html_content} };
            $self->{store}->{application}->{html_content} = [];
            return \@content;
        }
    }
}

=head2 debug

The debug method sets data to be output to the browser with additional information for debugging
purposes or if called with no parameters returns the data recorded and clears the data store.

=cut

sub debug {
    my ( $self, @debug ) = @_;
    if (@debug) {
        my @existing_debug =
          $self->{store}->{application}->{debug_content}
          ? @{ $self->{store}->{application}->{html_content} }
          : ();
        my ( $package, $filename, $line ) = caller;
        my $count = @existing_debug || 1;
        push @existing_debug, @debug;
        @existing_debug =
          map { $count . ". $_ at $package [$filename], on line $line." }
          @existing_debug;
        $self->{store}->{application}->{debug_content} = \@existing_debug;
        return \@existing_debug;
    }
    else {
        if ( $self->{store}->{application}->{debug_content} ) {
            my @content = @{ $self->{store}->{application}->{debug_content} };
            $self->{store}->{application}->{debug_content} = [];
            return \@content;
        }
    }
}

=head2 output

This method should be used with the debug or html methods to exit the application and spit out the passed in output.

=cut

sub output {
    my ( $self, @output ) = @_;
    $self->start();
    @output = @{ $output[0] } if ( ref( $output[0] ) eq "ARRAY" );
    foreach (@output) {
        print "$_<br/>\n";
    }
    exit;
}


=head2 plug

This function creates accessors for third party (non-core) modules, e.g.
$self->plug('email', sub{ return Email::Stuff->new(...) });

=cut

sub plug {
    my ( $self, $name, $init ) = @_;
    if ( $name && $init ) {
        no warnings 'redefine';
        no strict 'refs';
        my $routine = "SweetPea::$name";
        if ( ref $init eq "CODE" ) {
            *{$routine} = sub {
                $self->{".$name"} = $init->(@_) unless $self->{".$name"};
                return $self->{".$name"};
            };
        }
        else {
            *{$routine} = sub {
                $self->{".$name"} = $init unless $self->{".$name"};
                return $self->{".$name"};
            };
        }
    }
}

=head2 unplug

The unplug method re-initializes the accessor created by the plug method.

=cut

sub unplug {
    my ( $self, $name) = @_;
    delete $self->{".$name"};
}

=head2 makeapp

This function is exported an intended to be called from the command-line. This creates the boiler plate appication
structure.

=cut

sub makeapp {
    my $path          = $FindBin::Bin;
    my $app_structure = {
        "$path/.htaccess" => <<'EOF'
DirectoryIndex .pl
AddHandler cgi-script .pl .pm .cgi
Options +ExecCGI +FollowSymLinks -Indexes

RewriteEngine On
RewriteCond %{SCRIPT_FILENAME} !-d
RewriteCond %{SCRIPT_FILENAME} !-f
RewriteRule (.*) .pl/$1 [L]
EOF
        ,
        "$path/.pl" => <<'EOF'
#!/usr/bin/perl -w

BEGIN {
    use FindBin;
    use lib $FindBin::Bin . '/sweet';
    use lib $FindBin::Bin . '/sweet/application';
}

use SweetPea;
use App;

# run application
SweetPea->new->run;
EOF
        ,
        "$path/sweet/application/Controller/Root.pm" => <<'EOF'
package Controller::Root;

# Controller::Root - Root Controller / Landing Page (Should Exist)

sub _begin {
    my ( $self, $s ) = @_;
}

sub _index {
    my ( $self, $s ) = @_;
    $s->forward('/sweet/welcome');
}

sub _end {
    my ( $self, $s ) = @_;
}

1;

EOF
        , "$path/sweet/application/Controller/Sweet.pm" => <<'EOF'
package Controller::Sweet;

# Controller::Sweet - SweetPea Introduction and Welcome Page
# This function displays a simple information page the application defaults to before development.
# This module should be removed before development.

sub welcome {
    my ( $self, $s ) = @_;

    #header
    $s->html(
	qq`
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
    <head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<title>SweetPea is Alive and Well - SweetPea, the PnP Perl Web Application Framework</title>
`
    );

    #stylesheet
    $s->html(
	qq`
	<style type="text/css">
	    body
	    {
		font-family:    Bitstream Vera Sans,Trebuchet MS,Verdana,Tahoma,Arial,helvetica,sans-serif;
		color:          #818F08;
	    }
	    h1
	    {
		background-color:#818F08;
		color:#FFFFFF;
		display:block;
		font-size:0.85em;
		font-weight:normal;
		left:0;
		padding-bottom:10px;
		padding-left:15px;
		padding-right:10px;
		padding-top:10px;
		position:absolute;
		right:0;
		top:0;
		margin: 0px;
	    }
	    h2
	    {
		background-color:#EFEEEE;
		font-size:1em;
		padding-bottom:5px;
		padding-left:5px;
		padding-right:5px;
		padding-top:5px;
	    }
	    #container
	    {
		position:absolute;
		font-size:0.8em;
		font-weight:normal;
		padding-bottom:10px;
		padding-left:15px;
		padding-right:10px;
		padding-top:10px;
		left:0;
		right:0;
		top:40px;
	    }
	    .issue
	    {
		color: #FF0000;
	    }
	    .highlight
	    {
		background-color:#EFEEEE;
		padding:1px;
	    }
	</style>
    </head>
    <body>
    <h1>Welcome Young GrassHopper, SweetPea is working.</h1>
    <div id="container">
`
    );

    # body
    my $path = $s->application->{path};
    $s->html("<div class=\"section\">");
    $s->html("<h2>Application Details</h2>");
    $s->html("<span>SweetPea is running under Perl <span class=\"highlight\">$]
    </span> and is located at <span class=\"highlight\">$path</span></span><br/>"
    );
    $s->html("</div>");
    $s->html(
	qq`
    </div>
    </body>
</html>
`
    );

}

1;

EOF
        , "$path/sweet/application/Model/Schema.pm" => <<'EOF'
package Model::Schema;
use strict;
use warnings;

1;

EOF
        , "$path/sweet/application/View/Main.pm" => <<'EOF'
package View::Main;
use strict;
use warnings;

1;

EOF
        , "$path/sweet/App.pm" => <<'EOF'
package App;

use warnings;
use strict;

# App - This module loads all third party modules and provides accessors to the calling module!

sub plugins {
    my ( $class, $base ) = @_;
    my $self = bless {}, $class;

    # load modules using the following procedure, they will be available to
    # the application as $s->nameofobject.
    # Note! Please use this section to add non-core plugins/modules.

    # e.g. $base->plug( 'view', sub { return View::Main->new(...) } );

    return $self;
}

1;    # End of App

EOF
        ,
        "$path/sweet/sessions"  => "",
        "$path/sweet/templates" => "",
        "$path/static"          => "",

    };

    # make application structure
    foreach my $fod ( keys %{$app_structure} ) {
        unless ( -e $fod ) {
            if ( $fod =~ /\.\w{1,}$/ ) {
                $fod =~ s/^$path//;
                my @folders = split /\//, $fod;
                if (@folders) {
                    my $file  = pop @folders;
                    my $fpath = $path;
                    foreach (@folders) {
                        $fpath .= "$_/";
                        mkdir( $fpath, 0754 ) if $fpath =~ /sweet/;
                        mkdir( $fpath, 0755 ) if $fpath !~ /sweet/;
                    }
                    if ( $fod =~ /sweet/ ) {
                        open IN, ">$path$fod" || die "Can't create $file, $!";
                        print IN $app_structure->{"$path$fod"};
                        close IN;
                        my $mode = ($fod =~ /App\.pm/) ? '0755' : '0754';
                        chmod $mode, "$path$fod";
                        print "Created file $fod (chmod 754) ...\n";
                    }
                    else {
                        open IN, ">$path$fod" || die "Can't create $file, $!";
                        print IN $app_structure->{"$path$fod"};
                        close IN;
                        chmod 0755, "$path$fod";
                        print "Created file $fod (chmod 755) ...\n";
                    }
                }
                else {
                    $fod =~ s/^$path//;
                    open IN, ">$fod" || die "Can't create $fod, $!";
                    print IN $app_structure->{$fod};
                    close IN;
                    chmod 0755, "$fod";
                    print "Created file $fod (chmod 755) ...\n";
                }
            }
            else {
                $fod =~ s/^$path//;
                my @folders = split /\//, $fod;
                if (@folders) {
                    my $fpath = $path;
                    foreach (@folders) {
                        $fpath .= "$_/";
                        mkdir( $fpath, 0754 ) if $fpath =~ /sweet/;

             #print "Created dir $fpath (chmod 754) ...\n" if $fpath =~ /sweet/;
                        mkdir( $fpath, 0755 ) if $fpath !~ /sweet/;

             #print "Created dir $fpath (chmod 755) ...\n" if $fpath !~ /sweet/;
                    }
                }
                else {
                    mkdir( $path, 0755 );

                    #print "Created dir $path (chmod 755) ...\n";
                }
            }
        }
    }

}

=head1 AUTHOR

Al Newkirk, C<< <al at alnewkirk.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-sweetpea at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=SweetPea>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc SweetPea


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=SweetPea>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/SweetPea>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/SweetPea>

=item * Search CPAN

L<http://search.cpan.org/dist/SweetPea/>

=back


=head1 ACKNOWLEDGEMENTS

Thanks to all the developers of Mojolicious and Catalyst that inspired this.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Al Newkirk.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;    # End of SweetPea