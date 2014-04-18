use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack::Proto;
use DR::Tarantool::MsgPack qw(msgpack msgunpack msgcheck);
use base qw(Exporter);
our @EXPORT_OK = qw(call_lua response);
use Carp;
use Data::Dumper;

my (%resolve, %tresolve);

BEGIN {
    my %types = (
        IPROTO_SELECT              => 1,
        IPROTO_INSERT              => 2,
        IPROTO_REPLACE             => 3,
        IPROTO_UPDATE              => 4,
        IPROTO_DELETE              => 5,
        IPROTO_CALL                => 6,
        IPROTO_AUTH                => 7,
        IPROTO_DML_REQUEST_MAX     => 8,
        IPROTO_PING                => 64,
        IPROTO_SUBSCRIBE           => 66,
    );
    my %attrs = (
        IPROTO_CODE                => 0x00,
        IPROTO_SYNC                => 0x01,
        IPROTO_SERVER_ID           => 0x02,
        IPROTO_LSN                 => 0x03,
        IPROTO_TIMESTAMP           => 0x04,
        IPROTO_SPACE_ID            => 0x10,
        IPROTO_INDEX_ID            => 0x11,
        IPROTO_LIMIT               => 0x12,
        IPROTO_OFFSET              => 0x13,
        IPROTO_ITERATOR            => 0x14,
        IPROTO_KEY                 => 0x20,
        IPROTO_TUPLE               => 0x21,
        IPROTO_FUNCTION_NAME       => 0x22,
        IPROTO_USER_NAME           => 0x23,
        IPROTO_DATA                => 0x30,
        IPROTO_ERROR               => 0x31,
    );

    use constant;
    while (my ($n, $v) = each %types) {
        constant->import($n => $v);
        $n =~ s/^IPROTO_//;
        $tresolve{$v} = $n;
    }
    while (my ($n, $v) = each %attrs) {
        constant->import($n => $v);
        $n =~ s/^IPROTO_//;
        $resolve{$v} = $n;
    }
}



sub raw_response($) {
    my ($response) = @_;

    my $len;
    {
        return unless defined $response;
        my $lenheader = length $response > 10 ?
            substr $response, 0, 10 : $response;
        return unless my $lenlen = msgcheck($lenheader);

        $len = msgunpack($lenheader);
        croak 'Unexpected msgpack object ' . ref($len) if ref $len;
        $len += $lenlen;
    }

    return if length $response < $len;

    my @r;
    my $off = 0;

    for (1 .. 3) {
        my $sp = $off ? substr $response, $off : $response;
        my $len_item = msgcheck $sp;
        croak 'Broken response'
            unless $len_item and $len_item + $off <= length $response;
        push @r => msgunpack $sp;
        $off += $len_item;
    }

    croak 'Broken response header' unless 'HASH' eq ref $r[1];
    croak 'Broken response body' unless 'HASH' eq ref $r[2];

    return [ $r[1], $r[2] ], substr $response, $off;
}

sub response($) {

    my ($resp, $tail) = raw_response($_[0]);
    return unless $resp;
    my ($h, $b) = @$resp;

    my $res = {};

    while(my ($k, $v) = each %$h) {
        my $name = $resolve{$k};
        $name = $k unless defined $name;
        $res->{$name} = $v;
    }
    while(my ($k, $v) = each %$b) {
        my $name = $resolve{$k};
        $name = $k unless defined $name;
        $res->{$name} = $v;
    }

#     if (defined $res->{CODE}) {
#         my $n = $tresolve{ $res->{CODE} };
#         $res->{CODE} = $n if defined $n;
#     }

    return $res;
    
}

sub request($$) {
    my ($header, $body) = @_;
    my $pkt = msgpack($header) . msgpack($body);
    return msgpack(length $pkt) . $pkt;
}

sub call_lua($$@) {
    my ($sync, $proc, @args) = @_;
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   $proc,
            IPROTO_TUPLE,           \@args,
        }
    ;
}

1;
