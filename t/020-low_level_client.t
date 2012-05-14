#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use constant PLAN       => 34;
use Test::More tests    => PLAN;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::LLClient', 'tnt_connect';
    use_ok 'DR::Tarantool::StartTest';
    use_ok 'File::Spec::Functions', 'catfile';
    use_ok 'File::Basename', 'dirname', 'basename';
    use_ok 'AnyEvent';
}

my $cfg_dir = catfile dirname(__FILE__), 'test-data';
ok -d $cfg_dir, 'directory with test data';
my $tcfg = catfile $cfg_dir, 'llc-easy.cfg';
ok -r $tcfg, $tcfg;

my $tnt = run DR::Tarantool::StartTest( -f => $tcfg );

SKIP: {
    unless ($tnt->started) {
        diag $tnt->log;
        skip "tarantool isn't started", PLAN - 7;
    }

    my $client;

    # connect
    for my $cv (condvar AnyEvent) {
        DR::Tarantool::LLClient->tnt_connect(
            port    => $tnt->primary_port,
            cb      => sub {
                $client = shift;
                $cv->send;
            }
        );

        $cv->recv;
    }
    unless ( isa_ok $client => 'DR::Tarantool::LLClient' ) {
        diag eval { decode utf8 => $client } || $client;
        last;
    }

    # ping
    for my $cv (condvar AnyEvent) {
        $client->ping(
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* ping reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', 65280, 'type';
                $cv->send;
            }
        );
        $cv->recv;
    }

    # insert
    for my $cv (condvar AnyEvent) {
        my $cnt = 3;
        $client->insert(
            0,
            1,
            [ pack('L<', 1), 'abc' ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* insert reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', 13, 'type';

                cmp_ok $res->{tuples}[0][0], '~~', pack('L<', 1), 'key';
                cmp_ok $res->{tuples}[0][1], '~~', 'abc', 'f1';

                $cv->send if --$cnt == 0;

            }
        );

        $client->insert(
            0,
            1,
            [ pack('L<', 2), 'cde' ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, 'insert reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', 13, 'type';

                cmp_ok $res->{tuples}[0][0], '~~', pack('L<', 2), 'key';
                cmp_ok $res->{tuples}[0][1], '~~', 'cde', 'f1';

                $cv->send if --$cnt == 0;

            }
        );
        $client->insert(
            0,
            3,
            [ pack('L<', 1), 'aaa' ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code} & 0x00002002, '~~', 0x00002002,
                    'insert reply code (already exists)';
                cmp_ok $res->{status}, '~~', 'error', 'status';
                cmp_ok $res->{type}, '~~', 13, 'type';
                like $res->{errstr}, qr{already exists}, 'errstr';
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }

    # select
    for my $cv (condvar AnyEvent) {
        my $cnt = 2;
        $client->select(
            0, #ns
            0, #idx
            0, #offset
            2, # limit
            [ [ pack 'L<', 1 ], [ pack 'L<', 2 ] ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* select reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', 17, 'type';

                cmp_ok
                    scalar(grep { $_->[1] ~~ 'abc' } @{ $res->{tuples} }),
                    '~~',
                    1,
                    'first tuple'
                ;
                cmp_ok
                    scalar(grep { $_->[1] ~~ 'cde' } @{ $res->{tuples} }),
                    '~~',
                    1,
                    'second tuple'
                ;
                $cv->send if --$cnt == 0;
            }
        );

        $client->select(
            0, #ns
            0, #idx
            0, #offset
            2, # limit
            [ [ pack 'L<', 3 ], [ pack 'L<', 4 ] ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, 'select reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', 17, 'type';

                ok !@{ $res->{tuples} }, 'empty response';
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }


}
