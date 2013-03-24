<?php
if ($_SESSION["logged_in"]) {
	
	$list_nas = false;
	
	$xtpl->title(_("Network-attached storage"));
	
	$export_add_target = '?page=nas&action=export_add_save';
	$mount_export_add_target = '?page=nas&action=mount_export_add_save';
	$mount_custom_add_target = '?page=nas&action=mount_custom_add_save';
	$mount_edit_target = '?page=nas&action=mount_edit_save';
	
	switch ($_GET["action"]) {
		case "export_add":
			export_add_form($export_add_target);
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
			
		case "export_add_save":
			if ($_POST["node"] && $_POST["path"])
				
				$ok = false;
				$m = new member_load($_SESSION["is_admin"] ? $_POST["member"] : $_SESSION["member"]["m_id"]);
				
				foreach (nas_root_list_where($_SESSION["is_admin"] ? '' : "user_export = 1") as $r_id => $r) {
					if ($r_id == $_POST["root_id"])
						$ok = true;
				}
				
				if ( ($path = is_ds_valid($_POST["path"])) === false ) {
					$xtpl->perex(_("Path contains forbidden characters"), '');
					export_add_form($export_add_target);
				} else if ($_SESSION["is_admin"] && ($ds = is_ds_valid($_POST["dataset"])) === false) {
					$xtpl->perex(_("Dataset contains forbidden characters"), '');
					export_add_form($export_add_target);
				} else if ($ok && $m->exists) {
					nas_export_add(
						$_SESSION["is_admin"] ? $_POST["member"] : $_SESSION["member"]["m_id"],
						$_POST["root_id"],
						$_SESSION["is_admin"] ? $ds : NULL,
						$path,
						$_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]),
						$_SESSION["is_admin"] ? $_POST["user_editable"] : -1
					);
					
					$list_nas = true;
				}
			break;
		
		case "export_edit":
			$e = nas_get_export_by_id($_GET["id"]);
			
			if (nas_can_user_manage_export($e)) {
				export_edit_form('?page=nas&action=export_edit_save', $e);
			}
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
			
		case "export_edit_save":
			if ($_GET["id"] && $_POST["quota_val"] && $_POST["quota_unit"]) {
				$e = nas_get_export_by_id($_GET["id"]);
				// FIXME: control if quota is not less than used
				
				if (nas_can_user_manage_export($e))
					nas_export_update($_GET["id"], $_POST["quota_val"] * (2 << $NAS_UNITS_TR[$_POST["quota_unit"]]), $_SESSION["is_admin"] ? $_POST["user_editable"] : -1);
				
				$xtpl->perex(_("Export updated."), '');
			}
			
			$list_nas = true;
			break;
		
		case "export_del":
			break;
		
		case "mount_add":
			mount_add_form($mount_export_add_target, $mount_custom_add_target);
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
		
		case "mount_export_add_save":
			if ($_POST["export_id"] && $_POST["dst"] && $_POST["vps_id"]) {
				$e = nas_get_export_by_id($_POST["export_id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if(is_mount_dst_valid($_POST["dst"]) === false) {
					$xtpl->perex(_("Destination contains forbidden characters"), '');
					mount_add_form($mount_export_add_target, $mount_custom_add_target);
				} elseif (nas_can_user_add_mount($e, $vps))
					nas_mount_add(
						$_POST["export_id"],
						$_POST["vps_id"],
						$_POST["access_mode"],
						0,
						"",
						$_POST["dst"],
						$_SESSION["is_admin"] ? $_POST["m_opts"] : NULL,
						$_SESSION["is_admin"] ? $_POST["u_opts"] : NULL,
						"nfs",
						$_POST["cmd_premount"],
						$_POST["cmd_postmount"],
						$_POST["cmd_preumount"],
						$_POST["cmd_postumount"],
						$_POST["mount_immediately"]
					);
			}
			
			$list_nas = true;
			break;
		
		case "mount_custom_add_save":
			if ($_SESSION["is_admin"] && $_POST["vps_id"] && $_POST["src"] && $_POST["dst"]) {
				$e = nas_get_export_by_id($_POST["export_id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if(is_mount_dst_valid($_POST["dst"]) === false) {
					$xtpl->perex(_("Destination contains forbidden characters"), '');
					mount_add_form($mount_export_add_target, $mount_custom_add_target);
				} elseif (nas_can_user_add_mount($e, $vps))
					nas_mount_add(
						0,
						$_POST["vps_id"],
						$_POST["access_mode"],
						$_POST["source_node_id"],
						$_POST["src"],
						$_POST["dst"],
						$_POST["m_opts"],
						$_POST["u_opts"],
						$_POST["type"],
						$_POST["cmd_premount"],
						$_POST["cmd_postmount"],
						$_POST["cmd_preumount"],
						$_POST["cmd_postumount"],
						$_POST["mount_immediately"]
					);
			}
			break;
		
		case "mount_edit":
			$m = nas_get_mount_by_id($_GET["id"]);
			$vps = new vps_load($m["vps_id"]);
			
			if (nas_can_user_manage_mount($m, $vps)) {
				mount_edit_form($mount_edit_target, $m);
			}
			
			$xtpl->sbar_add(_("Back"), '?page=nas');
			break;
		
		case "mount_edit_save":
			if ($_GET["id"] && ($_POST["export_id"] || $_POST["src"]) && $_POST["dst"]) {
				$m = nas_get_mount_by_id($_GET["id"]);
				$vps = new vps_load($_POST["vps_id"]);
				
				if ( ($dst = is_mount_dst_valid($_POST["dst"])) === false ) {
					$xtpl->perex(_("Destination contains forbidden characters"), '');
					mount_edit_form($mount_edit_target, $m);
				} else {
					if (nas_can_user_manage_mount($m, $vps))
						nas_mount_update(
							$_GET["id"],
							$_POST["export_id"],
							$_POST["vps_id"],
							$_POST["access_mode"],
							$_SESSION["is_admin"] ? $_POST["source_node_id"] : NULL,
							$_SESSION["is_admin"] ? $_POST["src"] : NULL,
							$dst,
							$_SESSION["is_admin"] ? $_POST["m_opts"] : NULL,
							$_SESSION["is_admin"] ? $_POST["u_opts"] : NULL,
							$_SESSION["is_admin"] ? $_POST["type"] : NULL,
							$_POST["cmd_premount"],
							$_POST["cmd_postmount"],
							$_POST["cmd_preumount"],
							$_POST["cmd_postumount"],
							$_POST["remount_immediately"]
						);
					
					$xtpl->perex(_("Mount updated."), '');
				}
			} else $xtpl->perex(_("Mount NOT updated."), '');
			
			$list_nas = true;
			break;
		
		case "mount_del":
			break;
			
		case "mount":
			if ($_GET["id"]) {
				$m = nas_get_mount_by_id($_GET["id"]);
				$vps = new vps_load($m["vps_id"]);
				
				if (nas_can_user_manage_mount($m, $vps))
					$vps->mount($m);
				
				$xtpl->perex(_("Mount scheduled."), '');
			} else $xtpl->perex(_("Mount id missing."), '');
			
			$list_nas = true;
			break;
			
		case "umount":
			if ($_GET["id"]) {
				$m = nas_get_mount_by_id($_GET["id"]);
				$vps = new vps_load($m["vps_id"]);
				
				if (nas_can_user_manage_mount($m, $vps))
					$vps->umount($m);
				
				$xtpl->perex(_("Umount scheduled."), '');
			} else $xtpl->perex(_("Mount id missing."), '');
			
			$list_nas = true;
			break;
		
		default:
			$list_nas = true;
			break;
	}
	
	if ($list_nas) {
		$xtpl->sbar_add(_("Add export"), '?page=nas&action=export_add');
		$xtpl->sbar_add(_("Add mount"), '?page=nas&action=mount_add');
			
		$xtpl->table_title(_("Exports"));
		$xtpl->table_add_category(_("Member"));
		$xtpl->table_add_category(_("Server"));
		if ($_SESSION["is_admin"])
			$xtpl->table_add_category(_("Dataset"));
		$xtpl->table_add_category(_("Path"));
		$xtpl->table_add_category(_("Quota"));
		$xtpl->table_add_category(_("Used"));
		$xtpl->table_add_category(_("Available"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		$exports = nas_list_exports();
		
		foreach ($exports as $e) {
			$xtpl->table_td($e["m_nick"]);
			$xtpl->table_td($e["label"]);
			if ($_SESSION["is_admin"])
				$xtpl->table_td($e["dataset"]);
			$xtpl->table_td($e["path"]);
			$xtpl->table_td(nas_size_to_humanreadable($e["export_quota"]));
			$xtpl->table_td(nas_size_to_humanreadable($e["export_used"]));
			$xtpl->table_td(nas_size_to_humanreadable($e["export_avail"]));
			
			if (nas_can_user_manage_export($e)) {
				$xtpl->table_td('<a href="?page=nas&action=export_edit&id='.$e["export_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
				$xtpl->table_td('<a href="?page=nas&action=export_del&id='.$e["export_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
			} else {
				$xtpl->table_td('');
				$xtpl->table_td('');
			}
			
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
		
		$xtpl->table_title(_("Mounts"));
		$xtpl->table_add_category(_("VEID"));
		$xtpl->table_add_category(_("Source"));
		$xtpl->table_add_category(_("Destination"));
// 		$xtpl->table_add_category(_("Options"));
		$xtpl->table_add_category(_("Mount"));
		$xtpl->table_add_category(_("Umount"));
		$xtpl->table_add_category('');
		$xtpl->table_add_category('');
		
		$mounts = nas_list_mounts();
		
		foreach ($mounts as $m) {
			$xtpl->table_td($m["vps_id"]);
			$xtpl->table_td($m["storage_export_id"] ? $m["root_label"].":".$m["path"] : $m["server_name"].":".$m["src"]);
			$xtpl->table_td($m["dst"]);
// 			$xtpl->table_td($m["options"]);
			$xtpl->table_td('<a href="?page=nas&action=mount&id='.$m["mount_id"].'">'._("Mount").'</a>');
			$xtpl->table_td('<a href="?page=nas&action=umount&id='.$m["mount_id"].'">'._("Umount").'</a>');
			$xtpl->table_td('<a href="?page=nas&action=mount_edit&id='.$m["mount_id"].'"><img src="template/icons/edit.png" title="'._("Edit").'"></a>');
			$xtpl->table_td('<a href="?page=nas&action=mount_del&id='.$m["mount_id"].'"><img src="template/icons/delete.png" title="'._("Delete").'"></a>');
			$xtpl->table_tr();
		}
		
		$xtpl->table_out();
	}
	
	$xtpl->sbar_out(_("Manage NAS"));
	
} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
