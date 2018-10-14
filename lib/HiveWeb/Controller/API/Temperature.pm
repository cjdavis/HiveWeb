package HiveWeb::Controller::API::Temperature;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

sub index :Path :Args(0)
	{
	my ($self, $c) = @_;

	$c->detach('current');
	}

sub current :Local :Args(0)
	{
	my ($self, $c) = @_;

	my $wanted = $c->stash()->{in}->{temp};

	if ($wanted)
		{
		$wanted = [ $wanted ]
			if (ref($wanted) ne 'ARRAY');
		$wanted = map { $_ => 1 } @$wanted;
		}

	my $items = $c->model('DB::Item')->search({}, { order_by => 'me.display_name' });
	my $temps = [];
	while (my $item = $items->next())
		{
		next
			if ($wanted && !$wanted->{ $item->name() });
		my $temp = $item->search_related('temp_logs', {},
			{
			order_by => { -desc => 'create_time' },
			rows     => 1,
			prefetch => 'item',
			})->first();
		push (@$temps, $temp)
			if ($temp);
		}

	if ($temps)
		{
		$c->stash()->{out}->{temps}    = $temps;
		$c->stash()->{out}->{response} = \1;
		}
	}

__PACKAGE__->meta->make_immutable;

1;
