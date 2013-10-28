package Tube;

use Moo;

use POE;
use DDP;
use ZMQ::Constants qw(
  ZMQ_ROUTER
  ZMQ_IDENTITY
  ZMQ_SNDMORE
);
use Data::MessagePack;

use POSIX qw( floor );
use Time::HiRes qw( time gettimeofday tv_interval );

with 'POEx::ZMQ3::Role::Emitter';

has port => (
  is => 'ro',
  lazy => 1,
  default => sub { 12345 },
);
 
has host => (
  is => 'ro',
  lazy => 1,
  default => sub { '*' },
);

has players => (
  is => 'ro',
  lazy => 1,
  default => sub {{}},
);

has tickrate => (
  is => 'ro',
  lazy => 1,
  default => sub { 100 },
);

has tickdelay => (
  is => 'ro',
  lazy => 1,
  default => sub { 1 / $_[0]->tickrate },
);

has start_time => (
  is => 'ro',
  lazy => 1,
  default => sub { time },
);

sub current_tick {
  my ( $self ) = @_;
  my $diff = time - $self->start_time;
  return floor( $diff / $self->tickdelay );
}

has listen_on => (
  is => 'ro',
  default => sub { 'tcp://'.$_[0]->host.':'.$_[0]->port },
);

sub build_defined_states {
  my ($self) = @_;
  [ $self => [qw/
    emitter_started
    zmqsock_bind_added
    zmqsock_multipart_recv
    zmqsock_created
    zmqsock_closing
    tick
  /], ],
}

sub BUILD {
  my ( $self ) = @_;
  $self->start;
  $self->start_time;
}

sub zmqsock_bind_added { print "Listening to ".$_[ARG1]."\n" }
sub zmqsock_created { print "Created socket type ".$_[ARG1]."\n" }
sub zmqsock_closing { print "[".$_[ARG0]."] closing\n" }

# Protocol:
# first client sends 'needtick' message to register for ticks
# then server sends tick (and state, when we have it) updates to client
# and client sends tick-stamped state updates
#
# Each tick server gathers latest data for all clients, keeping a note of the
# differences in tick, sends

sub zmqsock_multipart_recv {
    my ( $from, $envelope, $data ) = @{$_[ARG1]};
    $data = Data::MessagePack->unpack($data);
    if ($data eq 'needtick') {
        # Initial 'registration' request
        print "[".sprintf("%10s",$from)."] need tick\n";
        $_[0]->players->{$from} = 0;
    
    } else {
        # State update from client
        my $diff = $_[0]->current_tick - $data;
        $_[0]->players->{$from} = $data;
        print "[".sprintf("%10s",$from)."] ".sprintf("%10d",$data)." ".sprintf("%10d",$diff)."\n" if $diff;
    }
}

sub start {
  my ( $self ) = @_;
  $self->zmq->start;
  $self->zmq->create( $self->alias, ZMQ_ROUTER );
  $self->zmq->set_zmq_sockopt( $self->alias, ZMQ_IDENTITY, 'SERVER' ); # do routers have identities? ... probably if we added P2P element (client-side router)
  $self->_start_emitter;
}

sub stop {
  my ( $self ) = @_;
  $self->zmq->stop;
  $self->_shutdown_emitter;
}

sub emitter_started {
  my ( $self ) = @_;
  $poe_kernel->call( $self->zmq->session_id, subscribe => 'all' );
  $self->add_bind( $self->alias, $self->listen_on );
  $poe_kernel->delay( tick => 1 );
}

sub tick {
  my ( $self ) = @_;
  print "tick ".$self->current_tick."\n";
  
  foreach(keys(%{$self->players})) {
      send_update_to_client($_);
  }
  
  $poe_kernel->delay( tick => $self->tickdelay );
}

sub send_update_to_client {
    my ($clientId) = @_;
    
    $_[0]->zmq->write( $_[0]->alias, $clientId, ZMQ_SNDMORE );
    $_[0]->zmq->write( $_[0]->alias, '', ZMQ_SNDMORE );
    $_[0]->zmq->write( $_[0]->alias, Data::MessagePack->pack($_[0]->current_tick) );
}

sub run { $poe_kernel->run }

1;
