package SweetPea;

BEGIN {
    use Config;
    use Exporter();
    use vars qw( @ISA @EXPORT @EXPORT_OK );
    @ISA    = qw( Exporter );
    @EXPORT = qw(sweet makeapp makectrl makeview makemodl makefile);
}

use CGI;
use CGI::Carp qw/fatalsToBrowser/;
use CGI::Cookie;
use CGI::Session;
use FindBin;
use File::Find;

our $VERSION = '2.25';

sub new {
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    #declare config stuff
    $self->{store}->{application}->{html_content}     = [];
    $self->{store}->{application}->{action_discovery} = 1;
    $self->{store}->{application}->{content_type}     = 'text/html';
    $self->{store}->{application}->{path}             = $FindBin::Bin;
    return $self;
}

sub run {
    my $self = shift;
    $self->_plugins;
    $self->_self_check;
    $self->_init_dispatcher;
    return $self;
}

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

    $self->plug(
        'session',
        sub {
            my $self = shift;
            CGI::Session->name("SID");
            my $sess = CGI::Session->new( "driver:file", undef,
                { Directory => $self->application->{path} . '/sweet/sessions' }
            );
            $sess->flush;
            return $sess;
        }
    );

    # load non-core plugins from App.pm
    eval 'use App';
    App->plugins($self) unless $@;

    return $self;
}

sub _load_path_and_actions {
    my $self = shift;

    if ( $self->application->{action_discovery} ) {
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
        map { $self->application->{actions}->{$_} = $actions->{$_} } keys %{$actions};
    }
    return $self->application->{actions};
}

sub _self_check {
    my $self = shift;

    # check manifest if available
    my $path = $self->application->{path};
    return $self;
}

sub _init_dispatcher {
    my $self = shift;

    my %dispatch = %{ $self->_load_path_and_actions() };
    my $path     = $self->cgi->path_info();
    $path =~ s/^\/\.pl//;
    $path =~ s/\/$//;
    $path = '/' unless $path;
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

    # restrict access to hidden methods (methods prefixed with an underscore)
    if ( $path =~ /.*\/_.*$/ ) {
        print $self->cgi->header, $self->cgi->start_html('Not found'),
          $self->cgi->h1('Access Denied'), $self->cgi->end_html;
        exit;
    }

    # set default action if action not defined
    # do recursive uri analysis
    my @action_params = ();    
    if ( not exists $dispatch{$path} ) {
        
        if (exists $dispatch{"$controller/_index"}) {
            $handler = $dispatch{"$controller/_index"};
        }
        
        # start recursive uri analysis
        my @controller = split /\//, $controller;
        
        for (my $i = 0; $i < @controller; $i++) {
            push @action_params, pop @controller;
            if (!$controller[0]) {
                if (exists $dispatch{'/'}) {
                    $handler = $dispatch{'/'};
                    $self->application->{'url'}->{controller} =
                    $controller = '/';
                    last;
                }
            }
            elsif (exists $dispatch{ join("/", @controller) }) {
                $handler = $dispatch{ join("/", @controller) };
                $self->application->{'url'}->{controller} = $controller =
                join("/", @controller);
                last;
            }
            elsif (exists $dispatch{ join("/", @controller) . "/_index" }) {
                $handler = $dispatch{ join("/", @controller) . "/_index" };
                $self->application->{'url'}->{controller} = $controller =
                join("/", @controller);
                last;
            }
        }
        
        # last resort, revert to root controller index action
        if (exists $dispatch{"/root/_index"} && (!$dispatch{"$controller"}
            && !$dispatch{"$controller/_index"})) {
            $handler = $dispatch{"/root/_index"};
        }        
    }
    # old way
    #unless ( exists $dispatch{$path} ) {
    #    $handler = $dispatch{"$controller/_index"}
    #      if exists $dispatch{"$controller/_index"};
    #    $handler = $dispatch{"/root/_index"}
    #      if exists $dispatch{"/root/_index"}
    #          && !$dispatch{"$controller/_index"};
    #}

    # parse and distribute action params if available
    if (defined $self->application->{action_params}->{$controller}) {
        $self->cgi->param(-name => $_, -value => pop @action_params)
        for @{$self->application->{action_params}->{$controller}};
    }

    if ( ref($handler) eq "CODE" ) {

        #run master _startup routine
        $dispatch{"/root/_startup"}->($self)
          if exists $dispatch{"/root/_startup"};

        #run user-defined begin routine or default to root begin

        $dispatch{"$controller/_begin"}->($self)
          if exists $dispatch{"$controller/_begin"};
        $dispatch{"/root/_begin"}->($self)
          if exists $dispatch{"/root/_begin"}
              && !$dispatch{"$controller/_begin"};

        # run both as opposed to either or global or local
        #$dispatch{"/root/_begin"}->($self)
        #  if exists $dispatch{"/root/_begin"};
        #$dispatch{"$controller/_begin"}->($self)
        #  if exists $dispatch{"$controller/_begin"};

        #run user-defined response routines
        $handler->($self);

        #run user-defined end routine or default to root end

        $dispatch{"$controller/_end"}->($self)
          if exists $dispatch{"$controller/_end"};
        $dispatch{"/root/_end"}->($self)
          if exists $dispatch{"/root/_end"} && !$dispatch{"$controller/_end"};

        # run both as opposed to either or global or local
        #$dispatch{"$controller/_end"}->($self)
        #  if exists $dispatch{"$controller/_end"};
        #$dispatch{"/root/_end"}->($self)
        #  if exists $dispatch{"/root/_end"};

        #run master _shutdown routine
        $dispatch{"/root/_shutdown"}->($self)
          if exists $dispatch{"/root/_shutdown"};

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

sub start {
    my $self = shift;

    # handle session
    if ( defined $self->session ) {
        $self->session->expire(
            defined $self->application->{session}->{expiration}
            ? $self->application->{session}->{expiration}
            : '1h' );
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

sub finish {
    my $self = shift;

    # print gathered html
    foreach ( @{ $self->html } ) {
        print "$_\n";
    }

    # commit session changes if a session has been created
    $self->session->flush();
}

sub forward {
    my ( $self, $path, $class ) = @_;

    #get actions
    my %dispatch = %{ $self->_load_path_and_actions() };

    #run requested routine
    $dispatch{"$path"}->( $self, $class ) if exists $dispatch{"$path"};
}

sub detach {
    my ( $self, $path, $class ) = @_;
    $self->forward( $path, $class );
    $self->start();
    $self->finish();
    exit;
}

sub redirect {
    my ( $self, $url ) = @_;
    $url = $self->url($url) unless $url =~ /^http/;
    print $self->cgi->redirect($url);
    exit;
}

sub store {
    my $self = shift;
    return $self->{store};
}

sub application {
    my $self = shift;
    return $self->{store}->{application};
}

sub content_type {
    my ( $self, $type ) = @_;
    $self->application->{content_type} = $type;
}

sub request_method {
    return $ENV{REQUEST_METHOD};
}

sub controller {
    my ( $self, $path ) = @_;
    return $self->uri->{controller} . ( $path ? $path : '' );
}

sub action {
    my $self = shift;
    return $self->uri->{action};
}

sub uri {
    my ( $self, $path ) = @_;
    return $self->{store}->{application}->{'url'} unless $path;
    $path =~ s/^\///; # remove leading slash for se with root
    return
        $self->cgi->url( -base => 1 )
      . $self->{store}->{application}->{'url'}->{'root'}
      . $path;
}

sub url { return shift->uri(@_); }

sub path {
    my ( $self, $path ) = @_;
    return $path
      ? $self->{store}->{application}->{'path'} . $path
      : $self->{store}->{application}->{'path'};
}

sub cookies {
    my $self = shift;
    return
      ref $self->{store}->{application}->{cookie_data} eq "ARRAY"
      ? @{ $self->{store}->{application}->{cookie_data} }
      : ();
}

sub flash {
    my ( $self, $message ) = @_;
    if ( defined $message ) {
        my $message = $self->session->param('_FLASH');
        $self->session->param( '_FLASH' => $message );
        return $message;
    }
    else {
        return $self->session->param('_FLASH');
    }
    $self->session->flush;
}

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

sub output {
    my ( $self, $seperator ) = @_;
    $self->start();
    @output = @{ ( defined $seperator ? $self->debug : $self->html ) };
    $seperator = "" unless defined $seperator;
    print join( $seperator, @output );
    exit;
}

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

sub unplug {
    my ( $self, $name ) = @_;
    delete $self->{".$name"};
    return $self;
}

sub routes {
    my ( $self, $routes ) = @_;
    map {
        my $url = $_;
        my @params = $url =~ m/\:([\w]+)/g;
        $url =~ s/\:[\w]+(\/)?//g; $url =~ s/\/$//;
        $url = '/' unless $url;
        $self->application->{actions}->{$url} = $routes->{$_};
        $self->application->{action_params}->{$url} = [@params];
    } keys %{$routes};
    return $self;
}

sub param {
    my ( $self, $name, $type ) = @_;
    if ( $name && $type ) {
        return (
                $type eq 'get' ? $self->cgi->url_param($name)
            : ( $type eq 'post' ? $self->cgi->param($name)
            : ( $type eq 'session' ? $self->session->param($name) : '' ) )
        );
    }
    elsif ( $name && !$type ) {
        return $self->cgi->url_param($name) if $self->cgi->url_param($name);
        return $self->cgi->param($name) if $self->cgi->param($name);
        return $self->session->param($name) if $self->session->param($name);
        return $self->application->{action_params}->{$self->controller}->{$name} if
        defined $self->application->{action_params}->{$self->controller}->{$name};
    }
    else {
        return 0;
    }
}

sub makeapp {
    my $path          = $FindBin::Bin;
    my $app_structure = {};

    #htaccess file
    $app_structure->{"$path/.htaccess"} = ""
      . 'DirectoryIndex .pl' . "\n"
      . 'AddHandler cgi-script .pl .pm .cgi' . "\n"
      . 'Options +ExecCGI +FollowSymLinks -Indexes' . "\n" . '' . "\n"
      . 'RewriteEngine On' . "\n"
      . 'RewriteCond %{SCRIPT_FILENAME} !-d' . "\n"
      . 'RewriteCond %{SCRIPT_FILENAME} !-f' . "\n"
      . 'RewriteRule (.*) .pl/$1 [L]' . "\n" . "";

    #router file
    $app_structure->{"$path/.pl"} =
        "" . '#!'
      . $Config{perlpath} . ' -w' . "\n" . '' . "\n"
      . 'BEGIN {' . "\n"
      . '    use FindBin;' . "\n"
      . '    use lib $FindBin::Bin . \'/sweet\';' . "\n"
      . '    use lib $FindBin::Bin . \'/sweet/application\';' . "\n" . '}'
      . "\n" . '' . "\n"
      . 'use SweetPea ' . $VERSION . ";\n"
      . "\n"
      . '# run application' . "\n"
      . 'sweet->run;' . "\n" . "";

    #default controller
    $app_structure->{"$path/sweet/application/Controller/Root.pm"} = ""
      . 'package Controller::Root;' . "\n" . '' . "\n"
      . '=head1 NAME' . "\n" . '' . "\n"
      . 'Controller::Root - Root Controller / Landing Page (Should Exist).'
      . "\n" . '' . "\n" . '=cut' . "\n" . '' . "\n"
      . 'sub _startup {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n" . '}' . "\n" . '' . "\n"
      . 'sub _begin {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n" . '}' . "\n" . '' . "\n"
      . 'sub _index {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n"
      . '    $s->forward(\'/sweet/welcome\');' . "\n" . '}' . "\n" . '' . "\n"
      . 'sub _end {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n" . '}' . "\n" . '' . "\n"
      . 'sub _shutdown {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n" . '}' . "\n" . '' . "\n" . '1;'
      . "\n" . '' . "\n" . "";

    #temporary welcome page
    $app_structure->{"$path/sweet/application/Controller/Sweet.pm"} = ""
      . 'package Controller::Sweet;' . "\n" . '' . "\n"
      . '=head1 NAME' . "\n" . '' . "\n"
      . 'Controller::Sweet - SweetPea Introduction and Welcome Page.' . "\n"
      . '' . "\n" . '=cut' . "\n" . '' . "\n"
      . '=head1 DESCRIPTION' . "\n" . '' . "\n"
      . 'This function displays a simple information page the application defaults to before development.'
      . "\n"
      . 'This module should be removed before development.' . "\n" . '' . "\n"
      . '=cut' . "\n" . '' . "\n"
      . 'sub welcome {' . "\n"
      . '    my ( $self, $s ) = @_;' . "\n"
      . '    my @html = ();' . "\n" . '' . "\n"
      . '    #header' . "\n"
      . '    push @html, "<!DOCTYPE html PUBLIC \\"-//W3C//DTD XHTML 1.0 Transitional//EN\\" \\"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\\">\n";'
      . "\n"
      . '    push @html, "<html xmlns=\\"http://www.w3.org/1999/xhtml\\">\n";'
      . "\n"
      . '    push @html, "    <head>\n";' . "\n"
      . '    push @html, "	<meta http-equiv=\\"Content-Type\\" content=\\"text/html; charset=utf-8\\" />\n";'
      . "\n"
      . '    push @html, "	<title>SweetPea is Alive and Well - SweetPea, the PnP Perl Web Application Framework</title>\n";'
      . "\n" . '' . "\n"
      . '    #stylesheet' . "\n"
      . '    push @html, "<style type=\\"text/css\\">\n";' . "\n"
      . '    push @html, "	    body\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		font-family:    Bitstream Vera Sans,Trebuchet MS,Verdana,Tahoma,Arial,helvetica,sans-serif;\n";'
      . "\n"
      . '    push @html, "		color:          #818F08;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	    h1\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		background-color:#818F08;\n";' . "\n"
      . '    push @html, "		color:#FFFFFF;\n";' . "\n"
      . '    push @html, "		display:block;\n";' . "\n"
      . '    push @html, "		font-size:0.85em;\n";' . "\n"
      . '    push @html, "		font-weight:normal;\n";' . "\n"
      . '    push @html, "		left:0;\n";' . "\n"
      . '    push @html, "		padding-bottom:10px;\n";' . "\n"
      . '    push @html, "		padding-left:15px;\n";' . "\n"
      . '    push @html, "		padding-right:10px;\n";' . "\n"
      . '    push @html, "		padding-top:10px;\n";' . "\n"
      . '    push @html, "		position:absolute;\n";' . "\n"
      . '    push @html, "		right:0;\n";' . "\n"
      . '    push @html, "		top:0;\n";' . "\n"
      . '    push @html, "		margin: 0px;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	    h2\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		background-color:#EFEEEE;\n";' . "\n"
      . '    push @html, "		font-size:1em;\n";' . "\n"
      . '    push @html, "		padding-bottom:5px;\n";' . "\n"
      . '    push @html, "		padding-left:5px;\n";' . "\n"
      . '    push @html, "		padding-right:5px;\n";' . "\n"
      . '    push @html, "		padding-top:5px;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	    #container\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		position:absolute;\n";' . "\n"
      . '    push @html, "		font-size:0.8em;\n";' . "\n"
      . '    push @html, "		font-weight:normal;\n";' . "\n"
      . '    push @html, "		padding-bottom:10px;\n";' . "\n"
      . '    push @html, "		padding-left:15px;\n";' . "\n"
      . '    push @html, "		padding-right:10px;\n";' . "\n"
      . '    push @html, "		padding-top:10px;\n";' . "\n"
      . '    push @html, "		left:0;\n";' . "\n"
      . '    push @html, "		right:0;\n";' . "\n"
      . '    push @html, "		top:40px;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	    .issue\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		color: #FF0000;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	    .highlight\n";' . "\n"
      . '    push @html, "	    {\n";' . "\n"
      . '    push @html, "		background-color:#EFEEEE;\n";' . "\n"
      . '    push @html, "		padding:1px;\n";' . "\n"
      . '    push @html, "	    }\n";' . "\n"
      . '    push @html, "	</style>\n";' . "\n" . '' . "\n"
      . '    # body' . "\n"
      . '    my $path = $s->application->{path};' . "\n" . '' . "\n"
      . '    push @html, "    </head>\n";' . "\n"
      . '    push @html, "    <body>\n";' . "\n"
      . '    push @html, "    <h1>Welcome Young GrassHopper, SweetPea is working.</h1>\n";'
      . "\n"
      . '    push @html, "    <div id=\\"container\\">\n";' . "\n"
      . '    push @html, "	<div class=\\"section\\">\n";' . "\n"
      . '    push @html, "	<h2>Application Details</h2>\n";' . "\n"
      . '    push @html, "	<span>SweetPea is running under Perl <span class=\\"highlight\\">$]</span> and is located at <span class=\\"highlight\\">$path</span></span><br/>\n";'
      . "\n"
      . '    push @html, "	</div>\n";' . "\n"
      . '    push @html, "    </div>\n";' . "\n"
      . '    push @html, "    </body>\n";' . "\n"
      . '    push @html, "</html>\n";' . "\n" . '' . "\n"
      . '    $s->html(join("", @html));' . "\n" . '' . "\n" . '}' . "\n" . ''
      . "\n" . '1;' . "\n" . '' . "\n" . "";

    # base model class
    $app_structure->{"$path/sweet/application/Model/Schema.pm"} = ""
      . 'package Model::Schema;' . "\n"
      . 'use strict;' . "\n"
      . 'use warnings;' . "\n" . '' . "\n" . '1;' . "\n" . '' . "\n" . "";

    # base view class
    $app_structure->{"$path/sweet/application/View/Main.pm"} = ""
      . 'package View::Main;' . "\n"
      . 'use strict;' . "\n"
      . 'use warnings;' . "\n" . '' . "\n" . '1;' . "\n" . '' . "\n" . "";

    $app_structure->{"$path/sweet/App.pm"} = ""
      . 'package App;' . "\n" . '' . "\n"
      . 'use warnings;' . "\n"
      . 'use strict;' . "\n" . '' . "\n"
      . '=head1 NAME' . "\n" . '' . "\n"
      . 'App - Loads modules and provides accessors to SweetPea.' . "\n" . ''
      . "\n" . '=cut' . "\n" . '' . "\n"
      . 'sub plugins {' . "\n"
      . '    my $s = pop @_;' . "\n" . '' . "\n"
      . '    # load modules using the following procedure, they will be available to'
      . "\n"
      . '    # the application as $s->nameofobject.' . "\n" . '' . "\n"
      . '    # Note! CGI (cgi), CGI::Cookie (cookie), and CGI::Session (session) '
      . "\n"
      . '    # plugins/modules are pre-loaded and available. ' . "\n" . ''
      . "\n"
      . '    # e.g. $s->plug( \'nameofobject\', sub { shift; return Module::Name->new(@_) } );'
      . "\n" . '' . "\n"
      . '    return $s;' . "\n" . '}' . "\n" . '' . "\n"
      . '1;    # End of App' . "\n" . '' . "\n" . "";

    $app_structure->{"$path/sweet/sessions"}  = "";
    $app_structure->{"$path/sweet/templates"} = "";
    $app_structure->{"$path/static"}          = "";

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
                        my $mode = '0755';
                        chmod $mode, "$path$fod";
                        print "Created file $fod (chmod 755) ...\n";
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
                        mkdir( $fpath, 0755 );
                    }
                }
                else {
                    mkdir( $path, 0755 );
                }
            }
        }
    }

    # secure sessions, and templates folders
    chmod 0700, "$path/sweet/sessions";
    chmod 0700, "$path/sweet/templates";
}

sub makemodl {
    my $data       = shift;
    my $controller = ( shift @ARGV ) || shift;
    my $syntax     = 'Please use, perl -MSweetPea -e makemodl model/name';
    my $root_path  = "$FindBin::Bin/sweet/application/Model/";
    my ( $module_name, $module_path ) = ();
    $controller =~ s/\.pm$//;
    $controller =~ s/[a-zA-Z0-9]\://g;
    if ($controller) {

        if ( $controller =~ /[\:\\\/\-]/ ) {
            my @folders = split /[\:\\\/\-]/, $controller;
            @folders = map( ucfirst, @folders );
            $module_name = "Model::" . join( "::", @folders );
            $controller = pop(@folders) . ".pm";

            # make folders
            my $tpath = $root_path;
            foreach my $path (@folders) {
                unless ( -e "$tpath$path" ) {
                    mkdir "$tpath$path";
                    chmod 0755, "$tpath$path";
                }
                $tpath = "$tpath$path/";
            }
            $module_path = $root_path . join( "/", @folders ) . "/$controller";
        }
        else {
            $module_name = "Model::" . ucfirst $controller;
            $module_path = $root_path . ucfirst($controller) . ".pm";
        }

        # create controller
        if ( not -e $module_path ) {
            open FILE,
              ">$module_path" || exit warn "Error creating $controller, $!";
            print FILE "package $module_name;\n";
            print FILE "\n";
            print FILE "=head1 NAME\n";
            print FILE "\n";
            print FILE "$module_name - Model Description.\n";
            print FILE "\n";
            print FILE "=cut\n";
            print FILE "\n";
            print FILE "$data\n" if $data;
            print FILE "\n";
            print FILE "1;";
            close FILE;
        }
        else {
            exit warn "$module_path already exists!\n";
        }
    }
    else {
        print "Failed making model.\n", $syntax;
        exit;
    }
}

sub makectrl {
    my $data       = shift;
    my $controller = ( shift @ARGV ) || shift;
    my $syntax     = 'Please use, perl -MSweetPea -e makectrl module/name';
    my $root_path  = "$FindBin::Bin/sweet/application/Controller/";
    my ( $module_name, $module_path ) = ();
    $controller =~ s/\.pm$//;
    $controller =~ s/[a-zA-Z0-9]\://g;
    if ($controller) {

        if ( $controller =~ /[\:\\\/\-]/ ) {
            my @folders = split /[\:\\\/\-]/, $controller;
            @folders = map( ucfirst, @folders );
            $module_name = "Controller::" . join( "::", @folders );
            $controller = pop(@folders) . ".pm";

            # make folders
            my $tpath = $root_path;
            foreach my $path (@folders) {
                unless ( -e "$tpath$path" ) {
                    mkdir "$tpath$path";
                    chmod 0755, "$tpath$path";
                }
                $tpath = "$tpath$path/";
            }
            $module_path = $root_path . join( "/", @folders ) . "/$controller";
        }
        else {
            $module_name = "Controller::" . ucfirst $controller;
            $module_path = $root_path . ucfirst($controller) . ".pm";
        }

        # create controller
        if ( not -e $module_path ) {
            open FILE,
              ">$module_path" || exit warn "Error creating $controller, $!";
            print FILE "package $module_name;\n";
            print FILE "\n";
            print FILE "=head1 NAME\n";
            print FILE "\n";
            print FILE "$module_name - Controller Description.\n";
            print FILE "\n";
            print FILE "=cut\n";
            print FILE "\n";
            print FILE "sub _begin {\n";
            print FILE "    my ( \$self, \$s ) = \@_;\n";
            print FILE "}\n";
            print FILE "\n";
            print FILE "sub _index {\n";
            print FILE "    my ( \$self, \$s ) = \@_;\n";
            print FILE "}\n";
            print FILE "\n";
            print FILE "sub _end {\n";
            print FILE "    my ( \$self, \$s ) = \@_;\n";
            print FILE "}\n";
            print FILE "\n";
            print FILE "$data\n" if $data;
            print FILE "\n";
            print FILE "1;";
            close FILE;
        }
        else {
            exit warn "$module_path already exists!\n";
        }
    }
    else {
        print "Failed making controller.\n", $syntax;
        exit;
    }
}

sub makeview {
    my $data       = shift;
    my $controller = ( shift @ARGV ) || shift;
    my $syntax     = 'Please use, perl -MSweetPea -e makeview view/name';
    my $root_path  = "$FindBin::Bin/sweet/application/View/";
    my ( $module_name, $module_path ) = ();
    $controller =~ s/\.pm$//;
    $controller =~ s/[a-zA-Z0-9]\://g;
    if ($controller) {

        if ( $controller =~ /[\:\\\/\-]/ ) {
            my @folders = split /[\:\\\/\-]/, $controller;
            @folders = map( ucfirst, @folders );
            $module_name = "View::" . join( "::", @folders );
            $controller = pop(@folders) . ".pm";

            # make folders
            my $tpath = $root_path;
            foreach my $path (@folders) {
                unless ( -e "$tpath$path" ) {
                    mkdir "$tpath$path";
                    chmod 0755, "$tpath$path";
                }
                $tpath = "$tpath$path/";
            }
            $module_path = $root_path . join( "/", @folders ) . "/$controller";
        }
        else {
            $module_name = "View::" . ucfirst $controller;
            $module_path = $root_path . ucfirst($controller) . ".pm";
        }

        # create controller
        if ( not -e $module_path ) {
            open FILE,
              ">$module_path" || exit warn "Error creating $controller, $!";
            print FILE "package $module_name;\n";
            print FILE "\n";
            print FILE "=head1 NAME\n";
            print FILE "\n";
            print FILE "$module_name - View Description.\n";
            print FILE "\n";
            print FILE "=cut\n";
            print FILE "\n";
            print FILE "$data\n" if $data;
            print FILE "\n";
            print FILE "1;";
            close FILE;
        }
        else {
            exit warn "$module_path already exists!\n";
        }
    }
    else {
        print "Failed making view.\n", $syntax;
        exit;
    }
}

sub makefile {
    my $data       = shift;
    my $controller = ( shift @ARGV ) || shift;
    my $syntax     = 'Please use, perl -MSweetPea -e makefile filename';
    my $root_path  = "$FindBin::Bin/";
    my ( $module_name, $module_path ) = ();
    if ($controller) {
        if ( $controller =~ /[\\\/\-]/ ) {
            my @folders = split /[\\\/\-]/, $controller;
            $controller = pop(@folders);

            # make folders
            my $tpath = $root_path;
            foreach my $path (@folders) {
                unless ( -e "$tpath$path" ) {
                    mkdir "$tpath$path";
                    chmod 0755, "$tpath$path";
                }
                $tpath = "$tpath$path/";
            }
            $module_path = $root_path . join( "/", @folders ) . "/$controller";
        }
        else {
            $module_path = $root_path . $controller;
        }

        # create controller
        if ( not -e $module_path ) {
            open FILE,
              ">$module_path" || exit warn "Error creating $controller, $!";
            print FILE "$data\n" if $data;
            close FILE;
        }
        else {
            exit warn "$module_path already exists!\n";
        }
    }
    else {
        print "Failed making file.\n", $syntax;
        exit;
    }
}

sub sweet {
    return SweetPea->new;
}

1;

__END__

=head1 NAME

SweetPea - A web framework that doesn't get in the way, or suck.

=head1 VERSION

Version 2.25

=cut

=head1 SYNOPSIS

Oh how Sweet web application development can be ...

    ... at the cli (command line interface)
    
    # download, test and install
    cpan SweetPea
    
    # build your skeleton application
    cd web_server_root/htdocs/my_new_application
    perl -MSweetPea -e makeapp
    
    > Created file /sweet/App.pm (chmod 755) ...
    > Created file /.pl (chmod 755) ...
    > Created file /.htaccess (chmod 755) ...
    > Creat....
    > ...
    
    # in the generated .pl file (change the path to perl if neccessary)
    
    #!/usr/bin/perl -w
    use SweetPea;
    my $s = SweetPea->new->run;
    
That's all Folks.

=head1 DESCRIPTION

SweetPea is a modern web application framework that follows the MVC (Model,
View, Controller) design pattern using useful concepts from Mojolicious, Catalyst
and other robust web frameworks. SweetPea has a short learning curve, is
light-weight, as scalable as you need it to be, and requires little configuration.

=head1 EXPORTED

    makeapp (skeleton application generation)

=head1 HOW IT WORKS

SweetPea uses a simple MVC pattern and ideology for processing and
responding to requests from the users browser. Here is an example
request and response outlining how SweetPea behaves when a request
is received.
    
    # The request
    http://localhost/admin/auth/
    - The user requests http://localhost/admin/auth/ from the browser.
    
    # The simple MVC pattern
    http://localhost/(admin/auth/)
    - admin/auth either matches as a Controller or Controller/Action.
    - e.g. Controller::Admin::auth() or Controller::Admin::Auth::_index()
    
    # The response
    - .pl (dispatcher/router) invokes SweetPea->new->run
    - the run method loads all plugins and scans the controllers folder
    building a table of controller/actions for further dispatching.
    - the dispatching routine executes the global or local _begin method,
    then executes the action or global or local _index method, and
    finally executes the global or local _end method.
    - the start and finish methods are then called to create, render
    and finalize the response and output.
    
    # Other magic (not included)
    * SweetPea will support routing which is a very popular way of
    dispatching URLs. Using routes will disable the default method
    of discovering controllers and actions making the application
    more secure. SweetPea will default scanning the controllers
    folder if no routes are defined.

=head1 APPLICATION STRUCTURE

    /static                 ## static content (html, css) is stored here
    /sweet                  ## application files are stored here
        /application        ## MVC files are stored here
            /Controller     ## controllers are stored here
                Root.pm     ## default controller (should always exist)
                Sweet.pm    ## new application welcome page controller
            /Model          ## models are stored here
                Schema.pm   ## new application boiler-plate model 
            /View           ## views are stored here
                Main.pm     ## new application boiler-plate view
        /sessions           ## auto-generated session files are stored here
        /templates          ## templates and layouts can be stored here
        App.pm              ## module for loading plugins (other modules)
    /.htaccess              ## enables pretty-urls on apache w/mod-rewrite
    /.pl                    ## default dispatcher (controller/action router)

=head1 GENERATED FILES INFORMATION

=head2 sweet/application/Controller/Root.pm

I<Controller::Root>

    The Root.pm controller is the default controller similar in function to
    a directory index (e.g. index.html). When a request is received that can
    not be matched in the controller/action table, the root/index
    (or Controller::Root::_index) method is invoked. This makes the _index
    method of Controller::Root, a kind of global fail-safe or fall back
    method.
    
    The _begin method is executed before the requested action, if no action
    is specified in the request the _index method is used, The _end method
    is invoked after the requested action or _index method has been
    executed.
    
    The _begin, _index, and _end methods can exist in any controller and
    serves the same purposes described here. During application request
    processing, these special routines are checked for in the namespace of
    the current requested action's Controller, if they are not found then
    the (global) alternative found in the Controller::Root namespace will
    be used.

    The _startup method is a special global method that cannot be overridden
    and is executed first with each request. The _shutdown is executed last
    and cannot be overridden either.

    # Controller::RootRoot.pm
    package Controller::Root;
    sub _startup { my ( $self, $s ) = @_; }
    sub _begin { my ( $self, $s ) = @_; }
    sub _index { my ( $self, $s ) = @_; }
    sub _end { my ( $self, $s ) = @_; }
    sub _shutdown { my ( $self, $s ) = @_; }
    1;

=head2 sweet/application/Controller/Sweet.pm

I<Controller::Sweet>

    # Sweet.pm
    * A welcome page for the newly created application. (Safe to delete)

=head2 sweet/application/Model/Schema.pm

I<Model::Schema>

    # Model/Schema.pm
    The Model::Schema boiler-plate model package is were your data
    connection, accessors, etc can be placed. SweetPea does not impose
    a specific configuration style, please feel free to connect to your
    data in the best possible fashion. Here is an example of how one
    might use this empty package with DBIx::Class.
    
    # in Model/Schema.pm
    package Model::Schema;
    use base qw/DBIx::Class::Schema::Loader/;
    __PACKAGE__->loader_options(debug=>1);
    1;
    
    # in App.pm
    use Model::Schema;
    sub plugins {
        ...
        $s->plug('data', sub { shift; return Model::Schema->new(@_) });
    }
    
    # example usage in Controller/Root.pm
    sub _dbconnect {
        my ($self, $s) = @_;
        $s->data->connect($dbi_dsn, $user, $pass, \%dbi_params);
    }

=head2 sweet/application/View/Main.pm

I<View::Main>

    # View/Main.pm
    The View::Main boiler-plate view package is were your layout/template
    accessors and renders might be stored. Each view is in fact a package
    that determines how data should be rendered back to the user in
    response to the request. Examples of different views are as follows:
    
    View::Main - Main view package that renders layouts and templates
    based on the main application's user interface design.
    
    View::Email::HTML - A view package which renders templates to
    be emailed as HTML.
    
    View::Email::TEXT - A view package which renders templates to be
    emailed as plain text.
    
    Here is an example of how one might use this empty
    package with Template (template toolkit).
    
    # in View/Main.pm
    package View::Main;
    use base Template;
    sub new {
        return __PACKAGE__->new({
        INCLUDE_PATH => 'sweet/templates/',
        EVAL_PERL    => 1,
        });
    }
    1;
    
    # in App.pm
    use View::Main;
    sub plugins {
        ...
        $s->plug('view', sub{ shift; return View::Main->new(@_) });
    }
    
    # example usage in Controller/Root.pm
    sub _index {
        my ($self, $s) = @_;
        $s->view->process($input, { s => $s });
    }    
    
=head2 sweet/application/App.pm

I<App>

    # App.pm
    The App application package is the developers access point to
    configure and extend the application before request processing. This
    is typically done using the plugins method. This package contains
    the special and required plugins method. Inside the plugins method is
    were other Modules are loaded and Module accessors are created using
    the core "plug" method. The following is an example of App.pm usage.
    
    package App;
    use warnings;
    use strict;
    use HTML::FormFu;
    use HTML::GridFu;
    use Model::Schema;
    use View::Main;
    
    sub plugins {
        my ( $class, $s ) = @_;
        my $self = bless {}, $class;
        $s->plug( 'form', sub { shift; return HTML::FormFu->new(@_) } );
        $s->plug( 'data', sub { shift; return Model::Schema->new(@_) } );
        $s->plug( 'view', sub { shift; return View::Main->new(@_) } );
        $s->plug( 'grid', sub { shift; return HTML::GridFu->new(@_) } );
        return $s;
    }
    1;    # End of App

=head2 .htaccess

I<htaccess>

    # .htaccess
    The .htaccess file allows apache-type web servers that support
    mod-rewrite to automatically configure your application environment.
    Using mod-rewrite your application can make use of pretty-urls. The
    requirements for using .htaccess files with your SweetPea application
    are as follows:
    
    mod-rewrite support
    .htaccess support with Allow, Deny
    
    # in .htaccess
    DirectoryIndex .pl
    AddHandler cgi-script .pl .pm .cgi
    Options +ExecCGI +FollowSymLinks -Indexes
    
    RewriteEngine On
    RewriteCond %{SCRIPT_FILENAME} !-d
    RewriteCond %{SCRIPT_FILENAME} !-f
    RewriteRule (.*) .pl/$1 [L]

=head2 .pl

I<pl>

    # .pl
    The .pl file is the main application router/dispatcher. It is
    responsible for prepairing the application via executing all pre and
    post processing routines as well as directing requests to the
    appropriate controllers and actions.
    
    #!/usr/env/perl
    BEGIN {
        use FindBin;
        use lib $FindBin::Bin . '/sweet';
        use lib $FindBin::Bin . '/sweet/application';
    }
    use SweetPea;
    use App;
    SweetPea->new->run;


=head1 SPECIAL ROUTINES

=head2 _startup

    # _startup
    sub _startup {...}
    The _startup method is a special global method that cannot be overridden
    and is executed before any other methods automatically with each request.

=head2 _begin

    # _begin
    sub _begin {...}
    
    The begin method can exist both globally and locally, and will be
    automatically invoked per request. When a request is processed,
    SweetPea checks whether the _begin method exists in the namespace
    of the Controller being requested, if not it checks whether the
    _begin method exists in the Controller::Root namespace and
    executes that method. If you opt to keep and use the default
    controller Controller::Root, then its _begin method will be
    defined as the global _begin method and will be executed
    automatically with each request. The automatic execution of
    _begin in Controller::Root can be overridden by adding a _begin
    method to the namespace of the controller to be requested.
    
    This special method is useful for checking user permissions, etc.

=head2 _index

    # _index
    sub _index {...}
    
    The index method can exist both globally and locally, and will
    be automatically invoked *only* if an action is not specified.
    When a request is processed, SweetPea scans the controllers
    folder building a table of controllers and actions for
    dispatching. The dispatching routine executes attempts to
    execute the action, if no action is specified, it
    default to executing the global or local _index method
    looking locally first, then globally ofcourse. The automatic
    execution of _index in Controller::Root can be overridden by
    adding a _index method to the namespace of the controller to
    be requested.
    
    This special method acts as a directory index or index.html
    file in that it is executed when no other file (action) is
    specified.
    
=head2 _end

    # _end
    sub _end {...}
    
    The end method can exist both globally and locally, and will be
    automatically invoked per request. When a request is processed,
    SweetPea checks whether the _end method exists in the namespace
    of the Controller being requested, if not it checks whether the
    _end method exists in the Controller::Root namespace and
    executes that method. If you opt to keep and use the default
    controller Controller::Root, then its _end method will be
    defined as the global _end method and will be executed
    automatically with each request. The automatic execution of
    _end in Controller::Root can be overridden by adding a _end
    method to the namespace of the controller to be requested.
    
    This special method is useful for performing cleanup
    functions at the end of a request.

=head2 _shutdown

    # _shutdown
    sub _shutdown {...}
    The _shutdown method is a special global method that cannot be overridden
    and is executed after all other methods automatically with each request.

=head1 RULES AND SYNTAX

=head2 The anatomy of a controller method

    Controllers are used by SweetPea in an OO (object-oriented)
    fashion and thus, all controller methods should follow the
    same design as they are passed the same parameters.
    
    package Controller::Foo;
    
    sub bar {
        my ($self, $s) = @_;
        ...
    }
    
    1;
    
    The foo method above (as well as al other controller methods)
    are passed at least two objects, an instance of the current
    controller usually referred to as $self, and an instance of
    the SweetPea application object usually referred to as $s.
    
    Note! Actions prefixed with an underscore can not be
    displatched to using URLs.
    
=head2 How to use plugins (other modules)

    Plugins are a great way to extend the functionality of a
    SweetPea application. Plugins are defined in the application
    package App.pm inside of the special plugins method as
    follows:
    
    # inside of App.pm
    package App;
    ...
    use CPAN::Module;
    
    sub plugins {
        ...
        $s->plug( 'cpan', sub { shift; return CPAN::Module->new(@_) } );
        return $s;
    }
    ...
    
    # notice below how an accessor is created for the ficticious
    CPAN::Module in the SweetPea namespace
    
    # inside sweet/Controller/MyController.pm
    sub _index {
        my ($self, $s) = @_;
        $s->cpan->some_method(...);
    }
    
    # when $s->cpan is called, it creates (unless the object reference
    exists) and returns a reference to that module object. To create
    or initialize another object, simply call the unplu method on the
    object's name.
    
    # inside sweet/Controller/MyController.pm
    sub _index {
        my ($self, $s) = @_;
        my $foo = $s->cpan;
        my $bar = $s->cpan;
        my $baz = $s->unplug('cpan')->cpan;
    }
    
    # in the example above, $foo and $bar hold the same reference, but
    $baz is holding a new refernce as if it called CPAN::Module->new;

=head1 INSTANTIATION

=head2 new

    The new method initializes a new SweetPea object.
    
    # in your .pl or other index/router file
    my $s = SweetPea->new;

=head2 run

    The run method discovers
    controllers and actions and executes internal pre and post request processing
    routines.

    # in your .pl or other index/router file
    my $s = SweetPea->new->run; # start processing the request
    
    NOTE! CGI, CGI::Cookie, and CGI::Session are plugged in automatically
    by the run method.
    
    # accessible via $s->cgi, $s->cookie, and $s->session

=cut

=head1 CONTROLLERS AND ACTIONS

    Controllers are always created in the sweet/controller folder and defined
    under the Controller namespace, e.g. Controller::MyController. In keeping
    with simplicity, controllers and actions are actually packages and
    routines ( controller/action = package controller; sub action {...} ).
    
    NOTE! Actions prefixed with an underscore e.g. _foo can not be dispatched to
    using URLs but are listed in the dispatch table and are available to
    the forward, detach and many other methods that might invoke an
    action/method.

=head1 RAD METHODS

RAD (Rapid Application Development) methods assist in the creation
of common files, objects and funtionality. These methods reduce the tedium
that comes with creating web applications models, views and controllers.

=head2 makeapp

    This function is exported an intended to be called from the
    command-line. This creates the boiler plate appication structure.
    
    # e.g. at the command line
    perl -MSweetPea -e makeapp
    > Created file /sweet/App.pm (chmod 755) ...
    > Created file /.pl (chmod 755) ...
    > Created file /.htaccess (chmod 755) ...
    > Creat....
    > ...

=cut

=head2 makectrl

    This function is exported an intended to be called from the
    command-line. This method creates a controller with a boiler plate structure
    and global begin, index, and end methods.
    
    # e.g. at the command line
    perl -MSweetPea -e makectrl admin/auth
    > Created file /sweet/application/Controller/Admin/Auth.pm (chmod 755) ...

=cut

=head2 makemodl

    This function is exported an intended to be called from the
    command-line. This method creates a model with a boiler plate structure.
    
    # e.g. at the command line
    perl -MSweetPea -e makemodl csv/upload
    > Created file /sweet/application/Model/Csv/Upload.pm (chmod 755) ...

=cut

=head2 makeview

    This function is exported an intended to be called from the
    command-line. This method creates a view with a boiler plate structure.
    
    # e.g. at the command line
    perl -MSweetPea -e makeview email/html
    > Created file /sweet/application/View/Email/Html.pm (chmod 755) ...

=cut

=head2 makefile

    This function is exported an intended to be called from the
    command-line. This creates a file anywhere within the current
    application's structure. This method is useful for application
    styling which is not yet fully implemented (see Application Styling).
    
    # e.g. at the command line
    perl -MSweetPea -e makefile test.pl
    > Created file test.pl (chmod 755) ...

=cut

=head1 APPLICATION STYLING

    Application Styling, not yet implemented, is a form of user/community
    defined scaffolding which allows SweetPea developers to extend
    RAD (Rapid Application Development) functionality using the core
    helper methods (see Helper Methods). These scaffolding templates will be
    accessible via the SweetPea::Style::MyStyle namespace.
    
    e.g. SweetPea::Style::Default
    package SweetPea::Style::Default;
    use SweetPea;
    
    sub makemodl {
    my $sub = 'sub process {...}';
        SweetPea::makemodl( $sub, 'schema/foo' );
    }
    
    # More information will be made available soon.

=cut

=head1 HELPER METHODS

=head2 controller

    The action method returns the current requested MVC
    controller/package.
    
    # user requested http://localhost/admin/auth
    
    $controller = $s->controller
    # $controller is /admin
    
    $controller = $s->controller('services');
    # $controller is /admin/services
    
    # maybe useful for saying
    
    $s->forward( $s->controller('services') );
    # executes Controller::Admin::services()

=cut

=head2 action

    The action method returns the current requested MVC
    action.
    
    # user requested http://localhost/admin/auth
    
    $action = $s->action
    # $action is auth if auth is an action, blank if not

=cut

=head2 url/uri

    The url/uri methods returns a completed URI string
    or reference to root, here or path variables, e.g.
    
    # user requested http://localhost/admin/auth
    
    my $link = $s->url('static/index.html');
    # $link is http://localhost/static/index.html
    
    # $s->uri->{root} is http://localhost
    # $s->uri->{here} is http://localhost/admin/auth
    # $s->uri->{path} is /admin/auth

=cut

=head2 path

    The path method returns a completed path to root
    or location passed to the path method.
    
    # application lives at /domains/sweetapp
    
    my $path = $s->path;
    # $path is /domains/sweetapp
    
    my $path = $s->path('static/index.html');
    # $path is /domains/sweetapp/static/index.html

=cut

=head2 cookies

    Returns an array of cookies set throughout the request.
    ...
    foreach my $cookie (@{$s->cookies}) {
        # do something with the cookie data
    }

=cut

=head2 param

    The param methods is an all purpose shortcut to accessing CGI's url_param,
    param (post param method), and CGI::Session's param methods in that order.
    Convenient when all params have unique names.

=cut

=head1 CONTROL METHODS

=head2 start

    The start method should probably be named (startup) because
    it is the method which processes the request and performs
    various startup tasks.
    
    # is invoked automatically

=cut

=head2 finish

    The finish method performs various tasks in processing the
    response to the request.
    
    # is invoked automatically

=cut

=head2 forward

    The forward method executes a method in a namespace,
    then continues to execute instructions in the method it was
    called from.
    
    # in Controller::Admin
    sub auth {
        my ($self, $s) = @_;
        $s->forward('/admin/auth_success');
        # now im doing something else
    }
    
    sub auth_success {
        my ($self, $s) = @_;
        # im doing something
    }
    
    using forward to here was inefficient, one could have used
    $self->auth_success($s) because we are in the same package.

=cut

=head2 detach

    The detach method executes a method in a namespace, then
    immediately executes the special "_end" method which finalizes
    the request.
    
    # in Controller::Admin
    sub auth {
        my ($self, $s) = @_;
        $s->detach('/admin/auth_success');
        # nothing after is executed
    }
    
    sub auth_success {
        my ($self, $s) = @_;
        # im doing something
    }
    
    using forward to here was inefficient, one could have used
    $self->auth_success($s) because we are in the same package.

=cut

=head1 METHODS

=head2 store

    The store method is an accessor to the special "store"
    hashref. The store hashref is the functional equivilent
    of the stash method found in many other frameworks. It
    serves as place developers can save and retreive information
    throughout the request.
    
    $s->store->{important_stuff} = "This is top secret stuff";

=cut

=head2 application

    The application method is in accessor to the special
    "application" hashref. As the "store" hashref is where general
    application data is stored, the "application" hashref is where
    application configuration information is stored.
    
    $s->application->{content_type} = 'text/html';
    
    This is just an example, to change the content type please use
    $s->content_type('text/html');
    Content-Type is always 'text/html' by default.

=cut

=head2 content_type

    The content_type method set the desired output format for use
    with http response headers.
    
    $s->content_type('text/html');

=cut

=head2 request_method

    The request_method determines the method (either Get or Post) used
    to requests the current action.

=cut

=head2 flash

    The flash method provides the ability to pass a single string of data
    from request "A" to request "B", then that data is deleted as to prevent
    it from being passed to any additional requests.
    
    # set flash message
    my $message = $s->flash('This is a test flash message');
    # $message equals 'This is a test flash message'
    
    # get flash message
    my $message = $s->flash();
    # $message equals 'This is a test flash message'
    
    # clear flash message
    my $message = $s->flash('');
    # returns previous message then clears, $message equals ""

=cut

=head2 html

    The html method sets data to be output to the browser or if
    called with no parameters returns the data recorded and
    clears the data store.
    
    If the html store contains any data at the end of the request,
    it is output to the browser.
    
    # in Controller::Root
    sub _index {
        my ($self, $s) = @_;
        $s->html('this is a test');
        $self->my_two_cents($s);
    }
    
    sub my_two_cents {
        my ($self, $s) = @_;
        $s->html(', or maybe not');
    }
    
    "this is a test, or maybe not" is output to the browser
    
    # in Controller::Root
    
    my @data;
    
    sub _index {
        my ($self, $s) = @_;
        $s->html('this is a test');
        $self->forget_it($s);
    }
    
    sub forget_it {
        my ($self, $s) = @_;
        @data = @{$s->html};
    }
    
    Nothing is output to the browser as $s->html returns and
    array of data stored in it and clears itself
    
    # @data contains ['this is a test','or maybe not']

=cut

=head2 debug

    The debug method sets data to be output to the browser with
    additional information for debugging purposes or if called
    with no parameters returns the data recorded and clears the
    data store. debug() is the functional equivilent of html()
    but with a different purpose.

=cut

=head2 output

    This method spits out html or debug information stored using
    $s->html and/or $s->debug methods throughout the request. The
    output method takes one argument, an entry seperator, which
    if defined (empty or not) will output debug data, if not
    explicitly defined will output html data.
    
    $s->output;
    # outputs html data.
    
    $s->output(""); or $s->output("\n"); or $s->output("<br/>");
    # outputs debug data.

=cut

=head2 redirect

    This method redirects the request to the supplied url. If no url
    is supplied, the request is redirected to the default page as defined
    in your .htaccess or controller/Root.pm file.

=cut

=head2 plug

    The plugin method creates accessors for third party (non-core)
    modules, e.g.
    
    $self->plug('email', sub{ shift; return Email::Stuff->new(@_) });
    
    # allow you to to say
    # in Controller::Root
    
    sub _index {
        my ($self, $s) = @_;
        $self->email->to(...)->from(...)->etc...
    }
    
    
    # NOTE! plugins should be defined within the plugins methods of
    the App.pm package;

=cut

=head2 unplug

    The unplug method releases the reference to the module object
    used by the module accessor created by the plug method.
    
    # inside sweet/Controller/MyController.pm
    sub _index {
        my ($self, $s) = @_;
        my $foo = $s->cpan;
        my $bar = $s->cpan;
        my $baz = $s->unplug('cpan')->cpan;
    }
    
    # in the example above, $foo and $bar hold the same reference, but
    $baz is holding a new refernce as if it called CPAN::Module->new;
    as defined in the plugins method in App.pm

=cut

=head2 routes

    The routes methods ...

=cut

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

# End of SweetPea