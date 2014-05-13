use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack;
use Carp;
require DR::Tarantool;
use base qw(Exporter);
our @EXPORT_OK = qw(msgpack msgunpack msgcheck);

sub msgpack($) {
    DR::Tarantool::_msgpack($_[0])
}

sub msgunpack($;$) {
    my ($pkt, $utf8) = @_;
    $utf8 ||= 0;
    $utf8 &&= 1;
    DR::Tarantool::_msgunpack($pkt, $utf8)
}

sub msgcheck($) {
    DR::Tarantool::_msgcheck($_[0])
}

sub TRUE()  { DR::Tarantool::MsgPack::Bool->new(1) };
sub FALSE() { DR::Tarantool::MsgPack::Bool->new(0) };


package DR::Tarantool::MsgPack::Bool;
use Carp;
use overload
    'int'   => sub { ${ $_[0] } },
    '""'    => sub { ${ $_[0] } },
    'bool'  => sub { ${ $_[0] } }
;

sub new {
    my ($class, $v) = @_;
    my $bv = $v ? 1 : 0;
    return bless \$v => ref($class) || $class;
}

sub msgpack :method {
    my ($self) = @_;
    return scalar pack 'C', ($$self ? 0xC3 : 0xC2);
}


1;
