use utf8;
use strict;
use warnings;

package DR::Tarantool::MsgPack::Proto;
use DR::Tarantool::MsgPack qw(msgpack msgunpack msgcheck);
use base qw(Exporter);
our @EXPORT_OK = qw(call_lua response insert replace del update select);
use Carp;
use Data::Dumper;
use Scalar::Util 'looks_like_number';

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

    if (defined $res->{CODE}) {
        my $n = $tresolve{ $res->{CODE} };
        $res->{CODE} = $n if defined $n;
    }

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

sub insert($$$) {
    my ($sync, $space, $tuple) = @_;

    $tuple = [ $tuple ] unless ref $tuple;
    croak "Cant convert HashRef to tuple" if 'HASH' eq ref $tuple;

    if (looks_like_number $space) {
        return request
            {
                IPROTO_SYNC,        $sync,
                IPROTO_CODE,        IPROTO_INSERT,
                IPROTO_SPACE_ID,    $space,
            },
            {
                IPROTO_TUPLE,       $tuple,
            }
        ;
    }
    # HACK
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   "box.space.$space:insert",
            IPROTO_TUPLE,           $tuple,
        }
    ;
}

sub replace($$$) {
    my ($sync, $space, $tuple) = @_;

    $tuple = [ $tuple ] unless ref $tuple;
    croak "Cant convert HashRef to tuple" if 'HASH' eq ref $tuple;

    if (looks_like_number $space) {
        return request
            {
                IPROTO_SYNC,        $sync,
                IPROTO_CODE,        IPROTO_REPLACE,
                IPROTO_SPACE_ID,    $space,
            },
            {
                IPROTO_TUPLE,       $tuple,
            }
        ;
    }
    # HACK
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   "box.space.$space:replace",
            IPROTO_TUPLE,           $tuple,
        }
    ;
}
sub del($$$) {
    my ($sync, $space, $key) = @_;

    $key = [ $key ] unless ref $key;
    croak "Cant convert HashRef to key" if 'HASH' eq ref $key;

    if (looks_like_number $space) {
        return request
            {
                IPROTO_SYNC,        $sync,
                IPROTO_CODE,        IPROTO_DELETE,
                IPROTO_SPACE_ID,    $space,
            },
            {
                IPROTO_KEY,         $key,
            }
        ;
    }
    # HACK
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   "box.space.$space:delete",
            IPROTO_TUPLE,           $key,
        }
    ;
}


sub update($$$$) {
    my ($sync, $space, $key, $ops) = @_;
    croak 'Oplist must be Arrayref' unless 'ARRAY' eq ref $ops;
    $key = [ $key ] unless ref $key;
    croak "Cant convert HashRef to key" if 'HASH' eq ref $key;

    if (looks_like_number $space) {
        return request
            {
                IPROTO_SYNC,        $sync,
                IPROTO_CODE,        IPROTO_UPDATE,
                IPROTO_SPACE_ID,    $space,
            },
            {
                IPROTO_KEY,         $key,
                IPROTO_TUPLE,       $ops,
            }
        ;
    }
    # HACK
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   "box.space.$space:update",
            IPROTO_TUPLE,           [ $key, $ops ]
        }
    ;
}

sub select($$$$;$$$) {
    my ($sync, $space, $index, $key, $limit, $offset, $iterator) = @_;
    $iterator = 'EQ' unless defined $iterator;
    $offset ||= 0;
    $limit  = 0xFFFF_FFFF unless defined $limit;
    $key = [ $key ] unless ref $key;
    croak "Cant convert HashRef to key" if 'HASH' eq ref $key;

    if (looks_like_number $space and looks_like_number $index) {
        return request
            {
                IPROTO_SYNC,        $sync,
                IPROTO_CODE,        IPROTO_SELECT,
                IPROTO_SPACE_ID,    $space,
                IPROTO_INDEX_ID,    $index,
                IPROTO_LIMIT,       $limit,
                IPROTO_OFFSET,      $offset,
                IPROTO_ITERATOR,    $iterator
            },
            {
                IPROTO_KEY,         $key,
            }
        ;
    }

    # HACK
    request
        {
            IPROTO_SYNC,            $sync,
            IPROTO_CODE,            IPROTO_CALL,
        },
        {
            IPROTO_FUNCTION_NAME,   "box.space.$space.index.$index:select",
            IPROTO_TUPLE,           [
                $key,
                {
                    offset => $offset,
                    limit => $limit,
                    iterator => $iterator
                } 
            ]
        }
    ;

}


1;
