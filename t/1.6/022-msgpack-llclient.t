#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib ../../lib);
use lib qw(blib/lib blib/arch ../blib/lib
    ../blib/arch ../../blib/lib ../../blib/arch);

BEGIN {
    use constant PLAN       => 53;
    use Test::More;
    use DR::Tarantool::StartTest;

    unless (DR::Tarantool::StartTest::is_version('1.6', 2)) {

        plan skip_all => 'tarantool 1.6 is not found';
    } else {
        plan tests => PLAN;
    }
}

use Encode qw(decode encode);



BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool';
    use_ok 'File::Spec::Functions', 'catfile', 'rel2abs';
    use_ok 'File::Basename', 'dirname';
    use_ok 'AnyEvent';
    use_ok 'DR::Tarantool::MsgPack::LLClient';
}

my $cfg = catfile dirname(__FILE__), 'data', 'll.lua';
my $cfgg = catfile dirname(__FILE__), 'data', 'll-grant.lua';

ok -r $cfg, "-r config file ($cfg)";
ok -r $cfgg, "-r config file ($cfgg)";


my $t = DR::Tarantool::StartTest->run(
    family  => 2,
    cfg     => $cfg,
);

ok $t->started, 'tarantool was started';

my $tnt;

note 'connect';
for my $cv (AE::cv) {
    $cv->begin;
    DR::Tarantool::MsgPack::LLClient->connect(
        host        => '127.0.0.1',
        port        => $t->primary_port,
        cb      => sub {
            ($tnt) = @_;
            ok $tnt, 'connect callback';
            $cv->end;
        }

    );
   
    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}


note 'ping';

for my $cv (AE::cv) {
    $cv->begin;
    $tnt->ping(sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'ping response';
        ok exists $r->{CODE}, 'ping code';
        ok exists $r->{SYNC}, 'ping sync';
        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}

note 'call';

for my $cv (AE::cv) {
    $cv->begin;
    $tnt->call_lua('box.session.id', [], sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'call response';
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok exists $r->{ERROR}, 'exists error';
        like $r->{ERROR} => qr[Execute access denied], 'error text';
        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}

note 'auth';


for my $cv (AE::cv) {
    $cv->begin;
    $tnt->auth('user1', 'password1', sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'auth response';
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok exists $r->{ERROR}, 'exists error';
        like $r->{ERROR} => qr[User.*is not found], 'error text';
        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}

note
$t->admin(q[ box.schema.user.create('user1', { password = 'password1' }) ]);

for my $cv (AE::cv) {
    $cv->begin;
    $tnt->auth('user1', 'password2', sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'auth response';
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok exists $r->{ERROR}, 'exists error';
        like $r->{ERROR} => qr[Incorrect password supplied], 'error text';
        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}

note
$t->admin(q[ box.schema.user.grant('user1', 'read,write,execute', 'universe') ]);

for my $cv (AE::cv) {
    $cv->begin;
    $tnt->auth('user1', 'password1', sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'auth response';
#         note explain $r;
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok !exists $r->{ERROR}, "existn't error";
        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}

note 'call again';

for my $cv (AE::cv) {
    $cv->begin;
    $tnt->call_lua('box.session.id', [], sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'call response';
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok !exists $r->{ERROR}, 'exists not error';
        isa_ok $r->{DATA} => 'ARRAY', 'extsts data';
        is scalar @{ $r->{DATA} }, 1, 'count of tuples';
        cmp_ok $r->{DATA}[0], '>', 0, 'box.session.id';

        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}
for my $cv (AE::cv) {
    $cv->begin;
    $tnt->call_lua('box.session.id', sub {
        my ($r) = @_;
        isa_ok $r => 'HASH', 'call response';
        ok exists $r->{CODE}, 'exists code';
        ok exists $r->{SYNC}, 'exists sync';
        ok !exists $r->{ERROR}, 'exists not error';
        isa_ok $r->{DATA} => 'ARRAY', 'extsts data';
        is scalar @{ $r->{DATA} }, 1, 'count of tuples';
        cmp_ok $r->{DATA}[0], '>', 0, 'box.session.id';

        $cv->end;
    });

    my $timer;
    $timer = AE::timer 1.5, 0, sub { $cv->end };
    $cv->recv;
    undef $timer;

    ok $tnt => 'connector was saved';
}
