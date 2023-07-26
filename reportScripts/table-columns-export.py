import yaml, requests, json, sys , os, automationassets
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle,Spacer
from reportlab.lib import colors
from msal import ConfidentialClientApplication
from azure.storage.blob import BlobServiceClient

purview_account_name = automationassets.get_automation_variable("purview-account-name")
tenant_id = automationassets.get_automation_variable("tenant-id")
pdf_file_name = automationassets.get_automation_variable("pdf-name")
client_id = automationassets.get_automation_variable("client-id")
client_secret = automationassets.get_automation_variable("client-secret")
resource = automationassets.get_automation_variable("resource")
blob_connection_string = automationassets.get_automation_variable("blob_connection_string")
pdf_container = automationassets.get_automation_variable("pdf_container")

scope = ["https://purview.azure.net/.default"]

purview_endpoint = f"https://{purview_account_name}.purview.azure.com"
authority = f"https://login.microsoftonline.com/{tenant_id}"

# print(f"Tenand id : {tenant_id}")
# print(f"Purview Account : {purview_account_name}")
# print(f"Purview Endpoint : {purview_endpoint}")
# print(f"Authority : {authority}")
# print(f"Client Id: {client_id}")
# print(f"Client Secret: {client_secret}")
# print(f"scope: {scope}")

app = ConfidentialClientApplication(client_id, authority=authority, client_credential=client_secret)
result = app.acquire_token_for_client(scopes=scope)

access_token = result['access_token']

headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
          }



search_uri = f"{purview_endpoint}/catalog/api/search/query?api-version=2022-03-01-preview"

payload = json.dumps({
        "keywords": None,
        # "limit": limit,
        "filter": {
            "and": [
                {
                    "objectType": "Tables"
                }
                # ,
                # {
                #     "id": {
                #         "operator": "gt",
                #         "value": guid
                #     }

                # }
            ]
        },
        # "offset": 0,
        # "limit": limit,
        "orderby": [{
            "id": "asc"
        }]
    })

tables = json.loads(requests.request("POST",search_uri, data=payload,headers=headers).content)



# Get the column details for the retrieved tables

# Initialize the table that will hold all the information
# The final format is a dictionary with the below structure
# {
#  "Table1": {
#         "Column1": {
#             "data_type": "column1_data_type",
#             "column_length": column1_length,
#             "user_description":  "column user description"
#         },
#         "Column2": {
#             "data_type": "column2_data_type",
#             "column_length": column2_length,
#             "user_description":  "column user description"
#         }
# "Table2" :
#   ....etc....
# }
tables_final = {}
guid=''

# print(tables['value'])

# For each table
for table in tables['value'] :
    # print(f" TABLE : {table['id']},{table['name']}")

    guid = table['id']
    # Get the table details - which inlude all the columns along with their sepcification
    tables_details_uri = f"{purview_endpoint}/catalog/api/atlas/v2/entity/guid/{guid}"
    table_details = json.loads(requests.request("GET", tables_details_uri, headers=headers).content)
    # print(f"Printing table details: {json.dumps(table_details)}")
    
    # Insert an entry in the dictionary that will hold all the info
    # use the table name as the key
    tables_final[table['name']]={}
    # For each column of the table
    for column in table_details['referredEntities']:
        # Get the needed details
        # Currently name,data type and length are retrieved but could be adjusted accordingly if needed 
        column_name= table_details['referredEntities'][column]['attributes']['name']
        data_type=table_details['referredEntities'][column]['attributes']['data_type']
        column_length=table_details['referredEntities'][column]['attributes']['length']
        user_description=table_details['referredEntities'][column]['attributes']['userDescription']
        # Check if column has classifications assigned
        # Then it will include a "classifications" nested key with all the respective details
        if "classifications" in table_details['referredEntities'][column]:
            # One column may contain multiple classifications
            # Concatenate all of them separated with comma in a single variable
            column_classification =''
            for classification in table_details['referredEntities'][column]['classifications']:
                # Get classification type 
                classification_name = classification['typeName']
                # Get the description from the type using the Get Classification Def API
                classification_details_uri = f"{purview_endpoint}/catalog/api/atlas/v2/types/classificationdef/name/{classification_name}"                
                classification_details = json.loads(requests.request("GET", classification_details_uri, headers=headers).content)
                # Concatenate the value
                column_classification=column_classification+classification_details['description']+','
        else:
            column_classification = ''

        # Remove trailing comma from classification field
        if column_classification != '':
            column_classification = column_classification.rstrip(',')

        column_details={"data_type": data_type, "column_length": column_length, "user_description": user_description, "classification": column_classification }
        # print(f"table name : {table['name']}")
        # print(f"column details : {column_details}")

        # Insert on the final dictionary
        # On the table key and column subkey insert the column details
        # Column name is used as (nested) key and the rest of the details as nested values
        tables_final[table['name']][column_name] = column_details
        # print(f"Tables_final : {tables_final}")

# Generate the pdf document

doc = SimpleDocTemplate(pdf_file_name, pagesize=letter)
elements = []
attribute_names = ['Column Name','Data Type', 'Length', 'User Description', 'Classification']
# For each table
for table_name, columns in tables_final.items():
    table_content = []
    # Add header row with table name
    header_row = [table_name]
    table_content.append(header_row)
    
    # Add attribute header row
    # attribute_header_row = [''] + attribute_names
    table_content.append(attribute_names)
    
    # Add rows for each column with separate columns for attributes
    for column_name, attributes in columns.items():

        row = [column_name] + list(attributes.values())
        table_content.append(row)



    table = Table(table_content)

    # Add table style
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, 0), colors.gray),
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.whitesmoke),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
        ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE', (0, 0), (-1, 0), 12),
        ('BOTTOMPADDING', (0, 0), (-1, 0), 12),
        ('BACKGROUND', (0, 1), (-1, -1), colors.beige),
        ('GRID', (0, 0), (-1, -1), 1, colors.black),
        ('SPAN', (0, 0), (-1, 0)),  # Merge cells in the header row
        ('FONTNAME', (0, 0), (-1, 1), 'Helvetica-Bold'),  # Apply bold font to the second row
    ]))

    elements.append(table)
    # Add spacer with height 40 to separate the tables (adjust as needed) 
    elements.append(Spacer(1, 40))  

# Remove the last spacer
if elements:
    elements.pop()        

doc.build(elements)

# print("After pdf generation")
# print(table_content)


#Upload pdf to Blob Storage

# print("Print paths and files....")
# print(os.getcwd())
# print(os.listdir()) 

blob_service_client = BlobServiceClient.from_connection_string(blob_connection_string)
container_client=blob_service_client.get_container_client(pdf_container)
with open(file=os.path.join('C:\Windows\System32', pdf_file_name), mode="rb") as data:
   blob_client = container_client.upload_blob(name=pdf_file_name, data=data, overwrite=True)