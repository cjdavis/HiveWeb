#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . '/../lib';
use HiveWeb;
use HiveWeb::Schema;
use UUID;
use MIME::Base64;
use Getopt::Long;
use Email::MIME;
use Email::Address::XS;

my $do_smtp = 0;
my $delete  = 0;

GetOptions(
	'email'  => \$do_smtp,
	'delete' => \$delete,
);

my $c           = HiveWeb->new || die $!;
my $config      = $c->config();
my $app_config  = $config->{application};
my $mail_config = $config->{email};
my $schema      = HiveWeb::Schema->connect($config->{"Model::DB"}->{connect_info}) || die $!;
my $queue       = $schema->resultset('Action')->search({}, { order_by => ['priority', 'queued_at'] }) || die $!;
my $smtp;
my @emails;

while (my $action = $queue->next())
	{
	$schema->txn_do(sub
		{
		my $type = lc($action->action_type());
		my $message =
			{
			from      => $mail_config->{from},
			from_name => $mail_config->{from_name},
			};
		if ($type =~ s/^application\.//)
			{
			my $application = $schema->resultset('Application')->find($action->row_id());
			if (!$application)
				{
				warn 'Cannot find referenced application ' . $action->row_id();
				return;
				}
			UUID::parse($application->application_id(), my $bin);
			my $enc_app_id = encode_base64($bin, '');
			$message->{to} = $app_config->{email_address};
			$message->{subject} = 'Membership Application: ' . $application->member()->fname() . ' ' . $application->member()->lname() . ' [' . $enc_app_id . ']';
			if (exists($app_config->{$type}))
				{
				my $app_create    = $app_config->{$type};
				$message->{stash} =
					{
					application => $application,
					enc_app_id  => $enc_app_id,
					action      => $action,
					base_url    => $config->{base_url},
					};
				$message->{temp_plain} = $app_create->{temp_plain};
				}
			else
				{
				# Unknown action type; leave it alone.
				return;
				}
			}
		elsif ($type =~ s/^member\.//)
			{
			my $member = $schema->resultset('Member')->find($action->row_id());
			if (!$member)
				{
				warn 'Cannot find referenced member ' . $action->row_id();
				return;
				}
			my $member_config = $mail_config->{member};
			if (exists($member_config->{$type}))
				{
				if ($type =~ /^notify_/)
					{
					$message->{to} = $mail_config->{notify_to};
					}
				else
					{
					$message->{to} = { $member->email() => $member->fname() . ' ' . $member->lname() };
					}
				$message->{temp_plain} = $member_config->{$type}->{temp_plain};
				$message->{subject}    = $member_config->{$type}->{subject};
				$message->{stash}      =
					{
					member   => $member,
					base_url => $config->{base_url},
					};
				}
			else
				{
				# Unknown action type; leave it alone.
				return;
				}
			}
		elsif ($type eq 'notify.term')
			{
			my $survey = $schema->resultset('SurveyResponse')->find($action->row_id());
			if (!$survey)
				{
				warn 'Cannot find referenced survey ' . $action->row_id();
				return;
				}
			$message->{to}         = $mail_config->{notify_to};
			$message->{temp_plain} = $mail_config->{notify_term}->{temp_plain};
			$message->{subject}    = $mail_config->{notify_term}->{subject};
			$message->{stash}      =
				{
				survey   => $survey,
				base_url => $config->{base_url},
				};
			}
		elsif ($type eq 'storage.assign')
			{
			my $slot = $schema->resultset('StorageSlot')->find($action->row_id());
			if (!$slot)
				{
				warn 'Cannot find referenced slot ' . $action->row_id();
				return;
				}
			my $member             = $slot->member();
			$message->{to}         = { $member->email() => $member->fname() . ' ' . $member->lname() };
			$message->{temp_plain} = $mail_config->{assigned_slot}->{temp_plain};
			$message->{subject}    = $mail_config->{assigned_slot}->{subject};
			$message->{stash}      =
				{
				member   => $member,
				slot     => $slot,
				base_url => $config->{base_url},
				};
			}
		elsif ($type eq 'storage.request')
			{
			my $request = $schema->resultset('StorageRequest')->find($action->row_id());
			if (!$request)
				{
				warn 'Cannot find referenced request ' . $action->row_id();
				return;
				}
			$message->{to} = [];
			my $users = $schema->resultset('MemberMgroup')->search(
				{
				'mgroup.name' => 'storage',
				},
				{
				join     => 'mgroup',
				prefetch => 'member',
				});

			while (my $user = $users->next())
				{
				my $member = $user->member();
				push(@{ $message->{to} }, { $member->email() => $member->fname() . ' ' . $member->lname() });
				}

			$message->{temp_plain} = $mail_config->{requested_slot}->{temp_plain};
			$message->{subject}    = $mail_config->{requested_slot}->{subject};
			$message->{stash}      =
				{
				request  => $request,
				base_url => $config->{base_url},
				};
			}
		elsif ($type eq 'password.reset')
			{
			my $member = $schema->resultset('Member')->find($action->row_id());
			if (!$member)
				{
				warn 'Cannot find referenced member ' . $action->row_id();
				return;
				}
			my $token              = $member->create_related('reset_tokens', { valid => 1 });
			my $forgot             = $mail_config->{forgot};
			$message->{to}         = { $member->email() => $member->fname() . ' ' . $member->lname() };
			$message->{subject}    = $forgot->{subject};
			$message->{temp_plain} = $forgot->{temp_plain};
			$message->{stash}      =
				{
				token    => $token,
				member   => $member,
				base_url => $config->{base_url},
				};
			}
		else
			{
			# Unknown action type; leave it alone.
			return;
			}

		if (ref($message->{to}) ne 'ARRAY')
			{
			$message->{to} = [ $message->{to} ];
			}

		my @parts;

		if ($message->{temp_html})
			{
			push(@parts, Email::MIME->create(
				attributes =>
					{
					content_type => 'text/html',
					},
				body => $c->view('TT')->render($c, $message->{temp_html}, $message->{stash}),
				));
			}

		if ($message->{temp_plain})
			{
			push(@parts, Email::MIME->create(
				attributes =>
					{
					content_type => 'text/plain',
					},
				body => $c->view('TT')->render($c, $message->{temp_plain}, $message->{stash}),
				));
			}

		my $email = Email::MIME->create(
			attributes =>
				{
				content_type => 'multipart/alternative',
				},
			header_str =>
				[
				Subject => $message->{subject},
				From    => Email::Address::XS->new($message->{from_name}, $message->{from}),
				],
			parts => \@parts,
			);

		push (@emails,
			{
			email => $email,
			to    => $message->{to},
			from  => $message->{from},
			});

		$action->delete()
			if ($delete);
		});
	}

if ($do_smtp && scalar(@emails))
	{
	$smtp = Net::SMTP->new(%{$mail_config->{'Net::SMTP'}});
	die "Could not connect to server\n"
		if !$smtp;

	if (exists($mail_config->{auth}))
		{
		$smtp->auth($mail_config->{from}, $mail_config->{auth})
			|| die "Authentication failed!\n";
		}

	foreach my $message (@emails)
		{
		foreach my $to (@{ $message->{to} })
			{
			my $to_env;
			my $to_header;
			if (ref($to) eq 'HASH')
				{
				$to_env = (keys(%$to))[0];
				$to_header = Email::Address::XS->new((values(%$to))[0], $to_env);
				}
			else
				{
				$to_env = $to;
				$to_header = Email::Address::XS->new(undef, $to_env);
				}
			$message->{email}->header_str_set(To => $to_header->as_string());

			if ($do_smtp)
				{
				$smtp->mail('<' . $message->{from} . ">\n");
				$smtp->to('<' . $to_env . ">\n");
				$smtp->data();
				$smtp->datasend($message->{email}->as_string() . "\n");
				$smtp->dataend();
				}
			}
		}
	$smtp->quit();
	}
elsif (scalar(@emails))
	{
	foreach my $message (@emails)
		{
		print($message->{email}->as_string() . "\n");
		}
	}
