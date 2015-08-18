<?php

function print_newvps_page1() {
	global $xtpl, $api;
	
	$xtpl->title(_("Create a VPS: Select an environment (1/3)"));
	
	$xtpl->form_create('', 'get', 'newvps-step1', false);

	$xtpl->table_td(
		_("Environment").':'.
		'<input type="hidden" name="page" value="adminvps">'.
		'<input type="hidden" name="action" value="new2">'
	);
	$xtpl->form_add_select_pure('environment',
		resource_list_to_options($api->environment->list(), 'id',  'label', false),
		$_GET['environment']);
	$xtpl->table_tr();
	
	$xtpl->form_out(_("Next"));
}

function print_newvps_page2($env_id) {
	global $xtpl, $api;
	
	$xtpl->title(_("Create a VPS: Select a location (2/3)"));
	
	$xtpl->form_create('', 'get', 'newvps-step2', false);
	
	$env = $api->environment->show($env_id);
	
	$xtpl->table_td(
		_('Environment').':'.
		'<input type="hidden" name="page" value="adminvps">'.
		'<input type="hidden" name="action" value="new3">'.
		'<input type="hidden" name="environment" value="'.$env_id.'">'
	);
	$xtpl->table_td($env->label);
	$xtpl->table_tr();
	
	$choices = resource_list_to_options($api->location->list(array('environment' => $env_id)));
	$choices[0] = _('--- select automatically ---');
	
	$xtpl->form_add_select(_("Location").':', 'location', $choices, $_GET['location'],  '');
	
	$xtpl->form_out(_("Next"));
	
	$xtpl->sbar_add(_('Back'), '?page=adminvps&action=new&environment='.$env_id);
}

function print_newvps_page3($env_id, $loc_id) {
	global $xtpl, $api;
	
	if ($_SESSION['is_admin'])
		$xtpl->title(_("Create a VPS: Specify parameters"));
	else
		$xtpl->title(_("Create a VPS: Specify parameters (3/3)"));
	
	$xtpl->form_create('?page=adminvps&action=new4&environment='.$env_id.'&location='.$loc_id, 'post');
	
	if (!$_SESSION['is_admin']) {
		$env = $api->environment->show($env_id);
		
		$xtpl->table_td(_('Environment').':');
		$xtpl->table_td($env->label);
		$xtpl->table_tr();
		
		$xtpl->table_td(_('Location').':');
		$xtpl->table_td($loc_id ? $api->location->show($loc_id)->label : _('select automatically'));
		$xtpl->table_tr();
	}
	
	$xtpl->form_add_input(_("Hostname").':', 'text', '30', 'vps_hostname', $_POST['vps_hostname'], _("A-z, a-z"), 255);
	
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_select(_("Node").':', 'vps_server', resource_list_to_options($api->node->list(), 'id', 'domain_name'), $_POST['vps_server'], '');
		$xtpl->form_add_select(_("Owner").':', 'm_id', resource_list_to_options($api->user->list(), 'id', 'login'), $_SESSION['member']['m_id'], '');
	}
	
	$xtpl->form_add_select(_("OS template").':', 'vps_template', resource_list_to_options($api->os_template->list()), $_POST['vps_template'],  '');
	
	$params = $api->vps->create->getParameters('input');
	$vps_resources = array('memory' => 4096, 'cpu' => 8, 'diskspace' => 60*1024, 'ipv4' => 1, 'ipv6' => 1);
	
	$user_resources = $api->user->current()->cluster_resource->list(array(
		'environment' => $env_id,
		'meta' => array('includes' => 'environment,cluster_resource')
	));
	$resource_map = array();
	
	foreach ($user_resources as $r) {
		$resource_map[ $r->cluster_resource->name ] = $r;
	}
	
	foreach ($vps_resources as $name => $default) {
		$p = $params->{$name};
		$r = $resource_map[$name];
		
		$xtpl->table_td($p->label.':');
		$xtpl->form_add_number_pure(
			$name,
			$_POST[$name] ? $_POST[$name] : min($default, $r->free),
			$r->cluster_resource->min,
			$_SESSION['is_admin']
				? $r->cluster_resource->max
				: min($r->free, $r->cluster_resource->max),
			$r->cluster_resource->stepsize,
			unit_for_cluster_resource($name)
		);
		$xtpl->table_tr();
	}
	
	if ($_SESSION["is_admin"]) {
		$xtpl->form_add_checkbox(_("Boot on create").':', 'boot_after_create', '1', (isset($_POST['vps_hostname']) && !isset($_POST['boot_after_create'])) ? false : true, $hint = '');
		$xtpl->form_add_textarea(_("Extra information about VPS").':', 28, 4, 'vps_info', $_POST['vps_info'], '');
	}
	
	$xtpl->form_out(_("Create"));
	
	if ($_SESSION['is_admin'])
		$xtpl->sbar_add(_('Back'), '?page=adminvps');
	else
		$xtpl->sbar_add(_('Back'), '?page=adminvps&action=new2&environment='.$env_id.'&location='.$loc_id);
}

function vps_details_title($vps) {
	global $xtpl;
	
	$title = 'VPS <a href="?page=adminvps&action=info&veid='.$vps->id.'">#'.$vps->id.'</a> '._("details");

	if ($_SESSION["is_admin"])
		$xtpl->title($title.' '._("[Admin mode]"));
	else
		$xtpl->title($title.' '._("[User mode]"));
}

function vps_details_submenu($vps) {
	global $xtpl;

	if ($_GET['action'] != 'info')
		$xtpl->sbar_add(_('Back to details'), '?page=adminvps&action=info&veid='.$vps->id);

	if ($_SESSION['is_admin']) {
		$xtpl->sbar_add(_('Migrate VPS'), '?page=adminvps&action=offlinemigrate&veid='.$vps->id);
		$xtpl->sbar_add(_('Change owner'), '?page=adminvps&action=chown&veid='.$vps->id);
	}

	$xtpl->sbar_add(_('Clone VPS'), '?page=adminvps&action=clone&veid='.$vps->id);
	$xtpl->sbar_add(_('Swap VPS'), '?page=adminvps&action=swap&veid='.$vps->id);
}

function vps_details_suite($vps) {
	vps_details_title($vps);
	vps_details_submenu($vps);
}

function vps_owner_form($vps) {
	global $xtpl, $api;

	$xtpl->table_title(_('VPS owner'));
	$xtpl->form_create('?page=adminvps&action=chown&veid='.$vps->id, 'post');
	$xtpl->form_add_select(_("Owner").':', 'm_id',
		resource_list_to_options($api->user->list(), 'id', 'login', false),
		$vps->user_id);
	$xtpl->form_out(_("Go >>"));

	vps_details_suite($vps);
}

function vps_migrate_form($vps) {
	global $xtpl;

	$xtpl->table_title(_('Offline migration'));
	$xtpl->form_create('?page=adminvps&action=offlinemigrate&veid='.$vps->id, 'post');
	api_params_to_form($vps->migrate, 'input');
	$xtpl->form_out(_("Go >>"));
	
	vps_details_suite($vps);
}

function vps_clone_form($vps) {
	global $xtpl;

	$xtpl->table_title(_('Clone VPS'));
	$xtpl->form_create('?page=adminvps&action=clone&veid='.$vps->id, 'post');
	
	api_params_to_form($vps->clone, 'input', array(
		'vps' => function($vps) {
			return '#'.$vps->id.' '.$vps->hostname;
		},
		'node' => function($node) {
			return $node->domain_name;
		}
	));
	
	$xtpl->form_out(_("Go >>"));
	
	vps_details_suite($vps);
}

function vps_swap_form($vps) {
	global $xtpl;

	$xtpl->table_title(_('Swap VPS'));
	$xtpl->form_create('?page=adminvps&action=swap_preview&veid='.$vps->id, 'get', 'vps-swap', false);
	
	api_params_to_form($vps->swap_with, 'input', array('vps' => function($vps) {
		return '#'.$vps->id.' '.$vps->hostname;
	}));
	
	$xtpl->form_out(_("Continue"), null,
		'<input type="hidden" name="page" value="adminvps">'.
		'<input type="hidden" name="action" value="swap_preview">'.
		'<input type="hidden" name="veid" value="'.$vps->id.'">'
	);
	
	vps_details_suite($vps);
}

function format_swap_preview($vps, $hostname, $resources, $ips, $node) {
	$ips_tmp = array();
	
	foreach ($ips as $ip) {
		$ips_tmp[] = $ip->addr;
	}

	$ips = implode(",<br>\n", $ips_tmp);

	$s = <<<EOT
	<h3>VPS <a href="?page=adminvps&action=info&veid={$vps->id}">{$vps->id}</a></h3>
	<dl>
		<dt>Hostname:</dt>
		<dd>$hostname</dd>
		<dt>Node:</dt>
		<dd>{$node->domain_name}</dd>
		<dt>CPU:</dt>
		<dd>{$resources->cpu}</dd>
		<dt>Memory:</dt>
		<dd>{$resources->memory}</dd>
		<dt>Swap:</dt>
		<dd>{$resources->swap}</dd>
		<dt>IP addresses:</dt>
		<dd>$ips</dd>
	</dl>
EOT;
	return $s;
}

function vps_swap_preview_form($primary, $secondary, $opts) {
	global $xtpl, $api;
	
	$xtpl->table_title(_("Swap VPS {$primary->id} with {$secondary->id}"));
	$xtpl->form_create('?page=adminvps&action=swap&veid='.$primary->id, 'post');
	$xtpl->table_add_category(_('Now'));
	$xtpl->table_add_category("&rarr;");
	$xtpl->table_add_category(_('After swap'));

	$primary_ips = $primary->ip_address->list();
	$secondary_ips = $secondary->ip_address->list();

	$xtpl->table_td(
		format_swap_preview(
			$primary,
			$primary->hostname,
			$primary,
			$primary_ips,
			$primary->node
		)
	);
	
	$xtpl->table_td("&rarr;", false, false, '1', '2');

	$xtpl->table_td(	
		format_swap_preview(
			$secondary,
			$opts['hostname'] ? $primary->hostname : $secondary->hostname,
			$opts['resources'] ? $primary : $secondary,
			$primary_ips,
			$primary->node
		)
	);

	$xtpl->table_tr();

	$xtpl->table_td(
		format_swap_preview(
			$secondary,
			$secondary->hostname,
			$secondary,
			$secondary_ips,
			$secondary->node
		)
	);

	$xtpl->table_td(
		format_swap_preview(
			$primary,
			$opts['hostname'] ? $secondary->hostname : $primary->hostname,
			$opts['resources'] ? $secondary : $primary,
			$secondary_ips,
			$secondary->node
		)
	);

	$xtpl->table_tr(false, 'notoddrow');

	$xtpl->table_td($xtpl->html_submit(_('Cancel'), 'cancel'));
	$xtpl->table_td('');
	$xtpl->table_td(
		'<input type="hidden" name="vps" value="'.$secondary->id.'">'.
		($opts['hostname'] ? '<input type="hidden" name="hostname" value="1">' : '').
		($opts['resources'] ? '<input type="hidden" name="resources" value="1">' : '').
		($opts['configs'] ? '<input type="hidden" name="configs" value="1">' : '').
		$xtpl->html_submit(_('Go >>'), 'go'),
		false, false, '2'
	);

	$xtpl->table_tr();

	$xtpl->form_out_raw();
}

