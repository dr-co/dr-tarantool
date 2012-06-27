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

=head1 NAME

DR::Tarantool::StartTest - finds and starts tarantool on free port.

=head1 SYNOPSIS

 my $t = run DR::Tarantool::StartTest ( cfg => $file_spaces_cfg );

=head1 DESCRIPTION

The module tries to find and then to start B<tarantool_box>.

The module is used inside tests.


=head1 METHODS

=head2 run

Constructor. Receives the following arguments:

=over

=item cfg

path to tarantool.cfg

=back

=cut


sub run {
    my ($module, %opts) = @_;

    my $cfg_file = $opts{cfg} or croak "config file not defined";
    croak "File not found" unless -r $cfg_file;
    open my $fh, '<:encoding(UTF-8)', $cfg_file or die "$@\n";
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


=head2 started

Returns true if tarantool is found and started

=cut

sub started {
    my ($self) = @_;
    return $self->{started};
}


=head2 log

Returns tarantool logs

=cut

sub log {
    my ($self) = @_;
    return '' unless $self->{log} and -r $self->{log};
    open my $fh, '<encoding(UTF-8)', $self->{log};
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

    return unless open my $fh, '>:encoding(UTF-8)', $self->{cfg};

    print $fh "\n\n\n", $self->{cfg_data}, "\n\n\n";

    print $fh "slab_alloc_arena = 1.1\n";

    for (qw(admin_port primary_port secondary_port)) {
        printf $fh "%s = %s\n", $_, $self->{$_};
    }

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

    chdir $self->{cwd};

    # wait for starting tarantool
    for (my $i = 0; $i < 100; $i++) {
        last if IO::Socket::INET->new(
            PeerAddr => '127.0.0.1', PeerPort => $self->primary_port
        );

        sleep 0.01;
    }
}


=head2 primary_port

Returns tarantool primary port

=cut

sub primary_port { return $_[0]->{primary_port} }


=head2 tarantool_pid

Returns B<PID>

=cut

sub tarantool_pid { return $_[0]->{child} }


=head2 kill

Kills tarantool

=cut

sub kill :method {
    my ($self) = @_;

    if ($self->{child}) {
        kill 'TERM' => $self->{child};
        waitpid $self->{child}, 0;
        delete $self->{child};
    }
}

=head2 DESTROY

Destructor. Kills tarantool, removes temporary files.

=cut

sub DESTROY {
    my ($self) = @_;
    chdir $self->{cwd};
    return unless $self->{master} == $$;
    $self->kill;
    rmtree $self->{temp} if $self->{temp};
}

{
    my $start_port;

    sub _find_free_port {
        $start_port = 10000 unless defined $start_port;

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
}

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2011 Dmitry E. Oboukhov <unera@debian.org>
 Copyright (C) 2011 Roman V. Nikolaev <rshadow@rambler.ru>

 This program is free software, you can redistribute it and/or
 modify it under the terms of the Artistic License.

=head1 VCS

The project is placed git repo on github:
L<https://github.com/unera/dr-tarantool/>.

=cut

1;
