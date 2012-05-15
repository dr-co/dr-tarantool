use utf8;
use strict;
use warnings;

package DR::Tarantool::StartTest;
use Carp;
use File::Temp qw(tempfile tempdir);
use File::Path 'rmtree';
use File::Spec::Functions qw(catfile);
use Cwd;
use IO::Socket::INET;
use feature 'state';

=head1 NAME

DR::Tarantool::StartTest - finds and starts tarantool on free port.

=head1 SYNOPSIS

 my $t = run DR::Tarantool::StartTest ( cfg => $file_spaces_cfg );

=head1 DESCRIPTION

The module tries to find and then to start B<tarantool_box>.

=cut


sub run {
    my ($module, %opts) = @_;

    my $cfg_file = $opts{cfg} or croak "config file not defined";
    croak "File not found" unless -r $cfg_file;
    open my $fh, '<:utf8', $cfg_file or die "$@\n";
    local $/;
    my $cfg = <$fh>;

    my %self = (
        admin_port      => $module->_find_free_port,
        primary_port    => $module->_find_free_port,
        secondary_port  => $module->_find_free_port,
        cfg_data        => $cfg,
        master          => $$,
        cwd             => getcwd,
    );

    my $self = bless \%self => $module;
    $self->_start_tarantool;
    $self;
}

sub started {
    my ($self) = @_;
    return $self->{started};
}

sub log {
    my ($self) = @_;
    return '' unless $self->{log} and -r $self->{log};
    open my $fh, '<:utf8', $self->{log};
    local $/;
    my $l = <$fh>;
    return $l;
}

sub _start_tarantool {
    my ($self) = @_;
    $self->{temp} = tempdir;
    $self->{cfg} = catfile $self->{temp}, 'tarantool.cfg';
    $self->{log} = catfile $self->{temp}, 'tarantool.log';
    $self->{pid} = catfile $self->{temp}, 'tarantool.pid';

    return unless open my $fh, '>:utf8', $self->{cfg};

    print $fh "slab_alloc_arena = 0.1\n";
    print $fh "\n\n\n", $self->{cfg_data}, "\n\n\n";

    for (qw(admin_port primary_port secondary_port)) {
        printf $fh "%s = %s\n", $_, $self->{$_};
    }

    printf $fh "script_dir = %s\n", $self->{temp};
    printf $fh "pid_file = %s\n", $self->{pid};
    printf $fh qq{logger = "cat > %s"\n"}, $self->{log};

    close $fh;

    chdir $self->{temp};

    system "tarantool_box -c $self->{cfg} --check-config > $self->{log} 2>&1";
    return if $?;


    system "tarantool_box -c $self->{cfg} --init-storage >> $self->{log} 2>&1";
    return if $?;

    unless ($self->{child} = fork) {
        exec "tarantool_box -c $self->{cfg}";
        die "Can't start tarantool_box: $!\n";
    }

    $self->{started} = 1;
    sleep 1;

    chdir $self->{cwd};
}

sub primary_port { return $_[0]->{primary_port} };

sub kill :method {
    my ($self) = @_;

    if ($self->{child}) {
        kill 'TERM' => $self->{child};
        waitpid $self->{child}, 0;
        delete $self->{child};
    }
}

sub DESTROY {
    my ($self) = @_;
    chdir $self->{cwd};
    return unless $self->{master} == $$;
    $self->kill;
    rmtree $self->{temp} if $self->{temp};
}

sub _find_free_port {
    state $start_port = 10000;

    while( ++$start_port < 60000 ) {
        return $start_port if IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $start_port,
            Proto     => 'tcp',
            (($^O eq 'MSWin32') ? () : (ReuseAddr => 1)),
        );
    }

    croak "Can't find free port";
}

1;
