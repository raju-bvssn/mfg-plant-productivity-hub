/**
 * @description       :
 * @author            : Vineela Bijjam
 * @group             :
 * @last modified on  : 02-05-2025
 * @last modified by  : David Moruzzi
 * Modified By 			Date 				JIIRA
 * Prasen 				09/17/2025			SDPOCC-21555
 * Prasen 				10/02/2025			SDPOCC-22597
 **/

 public without sharing class UserProvisioningUtil {

	public static final string SALESFORCE_LICENSE = 'Salesforce';
	private static final String curntuserid = UserInfo.getUserId();
  
	public void provisionUserWithProfileAndPermsets(User user, Boolean isUpdateUser) {
        Long startTime = System.currentTimeMillis();
		Boolean shouldProcess = false;
		String personaStr = user.Persona__c;
		List < String > personaCollection = new List < String > ();
		Set < String > records = new Set < String > ();
		Profile profile = [SELECT Id, Name FROM Profile WHERE Id =: user.ProfileId LIMIT 1];
		List < Ad_Group_Mapping__mdt > adGroupMappings = new List < Ad_Group_Mapping__mdt >();
		Ad_Group_Mapping__mdt prioritizedPersona = null;
		Profile profileToBeAssigned = null;
		Set < String > publicGroupNames = new Set < String > ();
		Set < String > permissionSetGroupNames = new Set < String > ();
		Set < String > ocrmRegion = new Set < String > ();
		List < String > localeSidKey = new List < String > ();
		
        if (profile.Name == 'System Administrator') {return;}		
		// Check if we should process based on persona
		if (String.isNotBlank(personaStr)) {
			personaStr = (personaStr.indexOf('(') >= 0 && personaStr.indexOf(')') >= 0)
                ? personaStr.substringAfter('(').substringBefore(')')
                : personaStr;
			personaCollection = personaStr.split(',');
			
			for (String persona: personaCollection) {
				records.add(persona.trim());
			}
			// Query AD group mappings first to get the target profile name
			
			try {
				for(String persona : records) {
                    adGroupMappings.add(Ad_Group_Mapping__mdt.getInstance(persona)); 
                }
                
                adGroupMappings.sort(new AdGroupComparator());
			} catch (Exception e) {
				System.debug('Error querying AD group mappings: ' + e.getMessage());
                String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'UserProvisioningUtil-provisionUserWithProfileAndPermsets', e.getMessage(), 'Error querying AD group mappings'});
			}finally{
                Long endTime = System.currentTimeMillis();
            }
			
			// Process if we have mappings
			if (!adGroupMappings.isEmpty()) {
				prioritizedPersona = adGroupMappings.get(0);
				// Single profile query - get both current user profile and target profile
				try {
					Set<String> profileNames = new Set<String>();
					profileNames.add(prioritizedPersona.ProfileGroupName__c);
					
					List<Profile> profiles = [
						SELECT Id, Name, UserLicense.Name 
						FROM Profile 
						WHERE Id = :user.ProfileId OR Name = :prioritizedPersona.ProfileGroupName__c
					];
					
					// Find current user profile and target profile
					for (Profile p : profiles) {
						if (p.Id == user.ProfileId) {
							profile = p;
						}
						if (p.Name == prioritizedPersona.ProfileGroupName__c) {
							profileToBeAssigned = p;
						}
				}
					
					// Check if user is not System Administrator and has valid target profile and is not bypass
                    if (profileToBeAssigned != null) { shouldProcess = true; }
				} catch (Exception e) {
					System.debug('Error querying profiles: ' + e.getMessage());
                    String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'UserProvisioningUtil-provisionUserWithProfileAndPermsets', e.getMessage(), 'Error querying profiles'});
				}finally{
                    Long endTime = System.currentTimeMillis();
			}
	  	}

  
		// Process user provisioning if all conditions are met
		if (shouldProcess) {
			try {
				// Set user for downgrade/upgrade Salesforce license
				setUserForDowngradeUpgradeSalesforceLicense(user, profileToBeAssigned);
				
				// Prepare user permissions
				prepareUserPermissions(adGroupMappings, publicGroupNames, permissionSetGroupNames, ocrmRegion, localeSidKey);
				
				// Set OCRM region if available
				if (!ocrmRegion.isEmpty()) {
					user.GWB_Region__c = ocrmRegion.iterator().next();
					user.GM_ApplicableRegionAccess__c = String.join(ocrmRegion, ';');
				}
				// Set locale if available
				if (!localeSidKey.isEmpty() && isUpdateUser) {
					user.LocaleSidKey = localeSidKey.get(0);
				}
				
				// Assign call center - commented out
				// assignCallCenter(adGroupMappings, user);
				
				// Update the user
				update(user);
				
				// Process permission set groups
				processPermissionSetGroups(user, trimExtraSpaces(permissionSetGroupNames));
				
				// Process public groups
				processPublicGroups(user, trimExtraSpaces(publicGroupNames));
				
			} catch (Exception e) {
				System.debug('Error during user provisioning: ' + e.getMessage());
				System.debug('Stack trace: ' + e.getStackTraceString());
                String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'UserProvisioningUtil-provisionUserWithProfileAndPermsets', e.getMessage(), 'Error during user provisioning'});
				return; // Preserve original behavior - return immediately on error
			} finally{
                Long endTime = System.currentTimeMillis();
            }
		}
	}
  }
  
	private void setUserForDowngradeUpgradeSalesforceLicense(User user, Profile profileToBeAssigned) {
		String newPlatformProfileId = profileToBeAssigned.Id;
		if (user.profileId != newPlatformProfileId) {
			user.ProfileId = newPlatformProfileId;
			user.UserPermissionsSupportUser = false;
			if (isSalesforceLicenseNeeded(profileToBeAssigned.UserLicense.Name)) {
				user.UserPermissionsSupportUser = true;
			}
		}
	}
  
	private void prepareUserPermissions(List < Ad_Group_Mapping__mdt > adGroupMappings, Set < String > publicGroupNames,
	   Set < String > permissionSetGroupNames, Set < String > ocrmRegion, List < String > localeSidKey) {
	   for (Ad_Group_Mapping__mdt adGroup: adGroupMappings) {
		  String publicGroup = adGroup.PublicGroupName__c;
		  if (!string.isBlank(publicGroup)) {
			 List < String > publicGroupList = publicGroup.split(',');
			 publicGroupNames.addAll(publicGroupList);
			}
			String permissionSetGroup = adGroup.PermissionGroupSetName__c;
			if (!string.isBlank(permissionSetGroup)) {
				List < String > permissionSetGroupList = permissionSetGroup.split(',');
				permissionSetGroupNames.addAll(permissionSetGroupList);
			}
	
			if (!string.isBlank(adGroup.GWB_Region__c)) {
				ocrmRegion.add(adGroup.GWB_Region__c);
			}
	
			if (!string.isBlank(adGroup.LocaleSidKey__c)) {
				localeSidKey.add(adGroup.LocaleSidKey__c);
			}
		}
	}
  
	private static Boolean isSalesforceLicenseNeeded(String licenseName) {
	  	return SALESFORCE_LICENSE.equalsIgnoreCase(licenseName);
	}
  
	public static Set < String > trimExtraSpaces(Set < String > permissionSets) {
		Set < String > trimmedPermSets = new Set < String > ();
		for (String permsetName: permissionSets) {
			trimmedPermSets.add(permsetName.trim());
		}
	   return trimmedPermSets;
	}
 
	public static void processPermissionSetGroups(
	   User user,
	   Set < String > permissionSetGroupNames
	) {
	   List < PermissionSetAssignment > permissionSetGroupAssignments = [
		  SELECT
		  Id,
		  PermissionSetGroup.DeveloperName,
		  Assignee.Name,
		  Assignee.Profile.Name
		  FROM PermissionSetAssignment
		  WHERE AssigneeId =: user.Id AND PermissionSetGroupId != NULL
	   ];
	   Map < String, Id > permissionSetGroupAssignmentsMap = new Map < String, Id > ();
	   List < PermissionSetAssignment > deletePermSetgrouplist = new List < PermissionSetAssignment > ();
	   Set < String > insertPermSetgrouplist = new Set < String > ();
	   for (PermissionSetAssignment permSetAss: permissionSetGroupAssignments) {
		  permissionSetGroupAssignmentsMap.put(
			 permSetAss.PermissionSetGroup.DeveloperName,
			 permSetAss.Id
		  );
		  if (!permissionSetGroupNames.contains(permSetAss.PermissionSetGroup.DeveloperName)) {
			 // delete the permsetGroup
			 deletePermSetgrouplist.add(permSetAss);
		  }
	   }
	   for (String permSetGroupName: permissionSetGroupNames) {
		  String assignedPermSet = permSetGroupName.trim();
		  if (!permissionSetGroupAssignmentsMap.containsKey(assignedPermSet)) {
				// insert the permsetGroup
				insertPermSetgrouplist.add(assignedPermSet);
			}
		}
		try {
		  Database.delete(deletePermSetgrouplist, true, AccessLevel.SYSTEM_MODE);
	   } catch (DmlException e) {
		  System.debug('Error deleting permission set groups: ' + e.getMessage());
          String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'UserProvisioningUtil-processPermissionSetGroups', e.getMessage(), 'Error deleting permission set groups'});
	   }
 
	   List < PermissionSetgroup > permissionSetgroups = [
		  SELECT Id, Status
		  FROM PermissionSetgroup
		  WHERE DeveloperName IN: insertPermSetgrouplist
	   ];
		if (!permissionSetgroups.isEmpty()) {
			List < PermissionSetAssignment > newPermissionSetAssignments = new List < PermissionSetAssignment > ();
			for (PermissionSetgroup permissionSet: permissionSetgroups) {
				//System.debug('Assigning the new permissionsetGroup is <<' + permissionSet.Id);
				PermissionSetAssignment newPermissionSetAssignment = new PermissionSetAssignment();
				newPermissionSetAssignment.AssigneeId = user.Id;
				newPermissionSetAssignment.PermissionSetGroupId = permissionSet.Id;
				newPermissionSetAssignments.add(newPermissionSetAssignment);
			}
			upsert newPermissionSetAssignments;
		}
	}
  
	public static void processPublicGroups(User user, Set < String > publicGroupNames) {
	   List < GroupMember > publicGroupAssignmentsList = [
		  SELECT Id, GroupId, UserOrGroupId, Group.DeveloperName, Group.Type
		  FROM GroupMember
		  WHERE UserOrGroupId =: user.Id and Group.Type = 'Regular'
	   ];
	   Map < String, Id > publicGroupAssignmentsMap = new Map < String, Id > ();
		List < GroupMember > deletePublicgrouplist = new List < GroupMember > ();
		Set < String > insertPublicgrouplist = new Set < String > ();
	
		for (GroupMember publicGroupAssign: publicGroupAssignmentsList) {
			publicGroupAssignmentsMap.put(
			publicGroupAssign.Group.DeveloperName, publicGroupAssign.GroupId);
			if (!publicGroupNames.contains(publicGroupAssign.Group.DeveloperName)) {
			// delete the permsetGroup
				deletePublicgrouplist.add(publicGroupAssign);
			}
		}
		for (String publicGroupName: publicGroupNames) {
			String assignedPublicGrp = publicGroupName.trim();
			if (!publicGroupAssignmentsMap.containsKey(assignedPublicGrp)) {
			// insert the permsetGroup
			    System.debug('inserting the pg'+assignedPublicGrp);
				insertPublicgrouplist.add(assignedPublicGrp);
			}
		}
		try {
			Database.delete(deletePublicgrouplist, true, AccessLevel.SYSTEM_MODE);
	   } catch (DmlException e) {
		  System.debug('Error deleting public groups: ' + e.getMessage());
           String errorMsg = String.format('Exception occurred in {0}: {1}\nContext: {2}', new List<String>{'UserProvisioningUtil-processPublicGroups', e.getMessage(), 'Error deleting public groups:'});
	   }finally{
       }
 
	   List < Group > publicGroups = [
		  SELECT Id
		  FROM Group
		  WHERE DeveloperName IN: insertPublicgrouplist
	   ];
	   if (!publicGroups.isEmpty()) {
		  list < GroupMember > groupMembers = new List < GroupMember > ();
		  for (Group publicGroup: publicGroups) {
				GroupMember groupMember = new GroupMember();
				groupMember.GroupId = publicGroup.Id;
				groupMember.UserOrGroupId = user.Id;
				groupMembers.add(groupMember);
			}
            System.debug('upserting groupMembers << ' + groupMembers);
			upsert groupMembers;
		}
	}
  
	public String getSSOProviderName() {
	  Organization a_ORG = [SELECT Id, Name, IsSandbox FROM Organization];
  
	  if (a_ORG.IsSandbox) {
		return 'GMAzure_PreProd';
	  } else {
		return 'GMAzure';
	  }
	}
  
	/*
	public void assignCallCenter(
	   List < Ad_Group_Mapping__mdt > adGroupMappings,
	   User user
	) {
		Boolean shouldProcess = false;
		Set < String > callCenterNameSet = new Set < String > ();
		Set < String > telephonyPackageLicenseNameSet = new Set < String > ();
		Map < String, CallCenter > callCenterMap = new Map < String, CallCenter > ();
		Map < String, PackageLicense > packageLicenseMap = new Map < String, PackageLicense > ();
		List < PackageLicense > packageLicenseList = new List < PackageLicense > ();
		Map < String, UserPackageLicense > userPackageLicenseMap = new Map < String, UserPackageLicense > ();
		Boolean callCenterExists = false;
		List < UserPackageLicense > insertableUserPackageLicenseList = new List < UserPackageLicense > ();
		
		// Check if we should process based on input parameters
		if(user != null && adGroupMappings != null && !adGroupMappings.isEmpty()) {
			shouldProcess = true;
			
			// Prepare the sets of callcenter names and telephony package names
			for (Ad_Group_Mapping__mdt adGrpMapp: adGroupMappings) {
				if (String.isNotBlank(adGrpMapp.CallCenterName__c)) {
					callCenterNameSet.add(adGrpMapp.CallCenterName__c);
				}
				if (String.isNotBlank(adGrpMapp.TelephonyPackageLicenseName__c)) {
					telephonyPackageLicenseNameSet.add(adGrpMapp.TelephonyPackageLicenseName__c);
				}
			}
			
			// Check if we have any data to process
			if (callCenterNameSet.isEmpty()) {
				shouldProcess = false;
				user.CallCenterId = null;
			}
		}
		
		// Process only if we have valid data
		if (shouldProcess) {
			// Create maps of callcenter names to their records
			if (!callCenterNameSet.isEmpty()) {
				List < CallCenter > callCenterList = [
					SELECT Id, Name
					FROM CallCenter
					WHERE Name IN :callCenterNameSet
				];
				for (CallCenter cc: callCenterList) {
					callCenterMap.put(cc.Name, cc);
				}
			}
			
			// Create map of package license name to record
			if (!telephonyPackageLicenseNameSet.isEmpty()) {
				packageLicenseList = [
					SELECT Id, NamespacePrefix
					FROM PackageLicense
					WHERE NamespacePrefix IN :telephonyPackageLicenseNameSet
				];
				for (PackageLicense pl: packageLicenseList) {
					packageLicenseMap.put(pl.NamespacePrefix, pl);
				}
			}
			
			// Get existing user package licenses
			if (!packageLicenseList.isEmpty()) {
				List < UserPackageLicense > userPackageLicenseList = [
					SELECT Id, UserId, PackageLicenseId
					FROM UserPackageLicense
					WHERE UserId = :user.Id
					AND PackageLicenseId IN :packageLicenseList
				];
				for (UserPackageLicense upl: userPackageLicenseList) {
					userPackageLicenseMap.put(upl.UserId + '--' + upl.PackageLicenseId, upl);
				}
			}
			
			// Process call center assignment
			Set<String> maintainUniquenessKey = new Set<String>();
			for (Ad_Group_Mapping__mdt adGrpMapp: adGroupMappings) {
				String callCenterName = adGrpMapp.CallCenterName__c;
				String telephonyPackageLicenseName = adGrpMapp.TelephonyPackageLicenseName__c;
				
				CallCenter callCenter = callCenterMap.get(callCenterName);
				PackageLicense packageLicense = packageLicenseMap.get(telephonyPackageLicenseName);
				
				if (callCenter != null) {
					callCenterExists = true;
					user.CallCenterId = callCenter.Id;
					
					//check if package license exist
					if(packageLicense!=null){
						String key = user.Id + '--' + packageLicense.Id;
						if(!userPackageLicenseMap.containsKey(key) && !maintainUniquenessKey.contains(key)){
							UserPackageLicense userPackageLicense = new UserPackageLicense();
							userPackageLicense.UserId = user.Id;
							userPackageLicense.PackageLicenseId = packageLicense.Id;
							insertableUserPackageLicenseList.add(userPackageLicense);
							maintainUniquenessKey.add(key);
						}
					}
				}
			}
			
			// Handle case when no call center exists
			if (!callCenterExists) {
				user.CallCenterId = null;
				// Delete all existing user package licenses for this user
				List<UserPackageLicense> allUserPackageLicenses = [
					SELECT Id, UserId, PackageLicenseId
					FROM UserPackageLicense
					WHERE UserId = :user.Id
				];
				if (!allUserPackageLicenses.isEmpty()) {
					delete allUserPackageLicenses;
				}
			}
			
			// Insert new package licenses
			if (!insertableUserPackageLicenseList.isEmpty()) {
				insert insertableUserPackageLicenseList;
			}
		}
	}
	*/
  
     public class AdGroupComparator implements Comparator<Ad_Group_Mapping__mdt> {
         public Integer compare(Ad_Group_Mapping__mdt a, Ad_Group_Mapping__mdt b) {
             if (a.PriorityNbr__c == null && b.PriorityNbr__c == null) return 0;
             if (a.PriorityNbr__c == null) return 1;
             if (b.PriorityNbr__c == null) return -1;
             
             if (a.PriorityNbr__c < b.PriorityNbr__c) return -1;
             if (a.PriorityNbr__c > b.PriorityNbr__c) return 1;
             return 0;
		}
	}
 }