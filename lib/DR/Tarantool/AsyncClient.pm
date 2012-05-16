use utf8;
use strict;
use warnings;

package DR::Tarantool::AsyncClient;
use DR::Tarantool::LLClient;
use DR::Tarantool::Spaces;
use Carp;
use base qw(Exporter);

our @EXPORT_OK = qw(tarantool);

=head1 NAME

DR::Tarantool::AsyncClient - async client for L<tarantool|http://tarantool.org>

=head1 SYNOPSIS

    use DR::Tarantool::AsyncClient 'tarantool';

    DR::Tarantool::AsyncClient->connect(
        host    => '127.0.0.1',
        port    => 12345,
        spaces  => {
            0   => {
                name    => 'users',
                fields  => [
                    qw(login password role),
                    {
                        name    => 'counter',
                        type    => 'NUM'
                    }
                ],
                indexes => {
                    0   => 'login',
                    1   => [ qw(login password) ],
                }
            },
            2   => {
                name    => 'roles',
                fields  => [ qw(name title) ],
                indexes => {
                    0   => 'name',
                }
            }
        }
        sub {
            my ($client) = @_;
            ...
        }
    );

=cut


sub _split_args {

    if (@_ % 2) {
        my ($self, %opts) = @_;
        my $cb = delete $opts{cb};
        return ($self, $cb, %opts);
    }

    my $cb = pop;
    splice @_, 1, 0, $cb;
    return @_;
}


sub connect {
    my $class = shift;
    my ($cb, %opts);
    if ( @_ % 2 ) {
        $cb = pop;
        %opts = @_;
    } else {
        %opts = @_;
        $cb = delete $opts{cb};
    }
    croak 'callback is not defined' unless 'CODE' eq ref $cb;

    my $host = $opts{host} || 'localhost';
    my $port = $opts{port} or croak "port isn't defined";

    my $spaces = new DR::Tarantool::Spaces($opts{spaces});
    my $reconnect_period    = $opts{reconnect_period} || 0;
    my $reconnect_always    = $opts{reconnect_always} || 0;

    DR::Tarantool::LLClient->connect(
        host                => $host,
        port                => $port,
        reconnect_period    => $reconnect_period,
        reconnect_always    => $reconnect_always,
        sub {
            my ($client) = @_;

            my $self;
            if (ref $client) {
                $self = bless {
                    llc     => $client,
                    spaces  => $spaces,
                } => __PACKAGE__;
            } else {
                $self = $client;
            }

            $cb->( $self );
        }
    );

    return;

}

sub _llc { return $_[0]{llc} }


=head2 ping

Pings server.

    $client->ping(sub { my ($status) = @_; ... });

=head3 Arguments

=over

=item cb

=back

=cut

sub ping {
    my ($self, $cb, %opts) = &_split_args;
    $self->_llc->ping(sub {
        $self->{last_result} = $_[0];
        $cb->($_[0]{status} ~~ 'ok' ? 1 : 0);
    });
}

1;
