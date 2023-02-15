import re

def validate_credit_card(card_number):
    # Check if card number matches the required pattern
    if not re.match(r'^[456]\d{3}-?\d{4}-?\d{4}-?\d{4}$', card_number):
        return False

    # Remove hyphens if present
    card_number = card_number.replace('-', '')

    # Check if card number does not have 4 or more consecutive repeated digits
    if re.search(r'(\d)\1\1\1', card_number):
        return False

    # All checks passed, return True
    return True

## Main function
number_of_inputs = int(input())  
for i in range(number_of_inputs) :
    if not validate_credit_card(input()):
        print("Invalid")
    else:
        print("Valid")
