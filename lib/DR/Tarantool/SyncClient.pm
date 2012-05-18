use utf8;
use strict;
use warnings;

package DR::Tarantool::SyncClient;
use base 'DR::Tarantool::AsyncClient';
use AnyEvent;
use Devel::GlobalDestruction;
use Carp;


sub connect {
    my ($class, %opts) = @_;
    my $cv = condvar AnyEvent;
    my $self;

    $class->SUPER::connect(%opts, sub {
        ($self) = @_;
        $cv->send;
    });

    $cv->recv;

    croak $self unless ref $self;
    $self;
}


for my $method (qw(ping insert update delete call)) {
    no strict 'refs';
    *{ __PACKAGE__ . "::$method" } = sub {
        my ($self, @args) = @_;
        my @res;
        my $cv = condvar AnyEvent;
        eval "\$self->SUPER::$method(\@args, sub { \@res = \@_; \$cv->send })";
        $cv->recv;

        if ($res[0] ~~ 'ok') {
            return $res[1] // $res[0];
        }
        croak  "$res[1]: $res[2]";
    };
}

sub DESTROY {
    my ($self) = @_;
    return if in_global_destruction;

    my $cv = condvar AnyEvent;
    $self->disconnect(sub { $cv->send });
    $cv->recv;
}

1;
