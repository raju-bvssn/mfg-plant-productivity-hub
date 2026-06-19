// Create HQ Admin and Plant Admin demo users

Id minAccessProfileId = '00eHn000001AYPzIAO';
Id psHQAdmin    = '0PSHn0000038591OAA';
Id psPlantAdmin = '0PSHn0000038592OAA';

// --- HQ Admin user ---
User hqUser = new User(
    FirstName      = 'Alex',
    LastName       = 'Chen',
    Email          = 'alex.chen@plantiq-demo.com',
    Username       = 'alex.chen@plantiq-demo.com',
    Alias          = 'achen',
    ProfileId      = minAccessProfileId,
    TimeZoneSidKey = 'America/Detroit',
    LocaleSidKey   = 'en_US',
    LanguageLocaleKey = 'en_US',
    EmailEncodingKey  = 'UTF-8'
);

// --- Plant Admin user ---
User plantUser = new User(
    FirstName      = 'Jordan',
    LastName       = 'Smith',
    Email          = 'jordan.smith@plantiq-demo.com',
    Username       = 'jordan.smith@plantiq-demo.com',
    Alias          = 'jsmith',
    ProfileId      = minAccessProfileId,
    TimeZoneSidKey = 'America/Detroit',
    LocaleSidKey   = 'en_US',
    LanguageLocaleKey = 'en_US',
    EmailEncodingKey  = 'UTF-8'
);

insert new List<User>{ hqUser, plantUser };
System.debug('HQ User ID: ' + hqUser.Id);
System.debug('Plant User ID: ' + plantUser.Id);

// Assign permission sets
insert new List<PermissionSetAssignment>{
    new PermissionSetAssignment(AssigneeId = hqUser.Id,    PermissionSetId = psHQAdmin),
    new PermissionSetAssignment(AssigneeId = plantUser.Id, PermissionSetId = psPlantAdmin)
};
System.debug('Permission sets assigned.');

// Set passwords
System.setPassword(hqUser.Id,    'PlantIQ@HQ2026!');
System.setPassword(plantUser.Id, 'PlantIQ@SHA2026!');
System.debug('Passwords set.');
System.debug('HQ Admin login:    alex.chen@plantiq-demo.com  /  PlantIQ@HQ2026!');
System.debug('Plant Admin login: jordan.smith@plantiq-demo.com  /  PlantIQ@SHA2026!');
