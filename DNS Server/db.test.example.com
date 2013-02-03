$ORIGIN example.com.		  ; comment
$TTL 1h

;	explicit ttl
example.com. 1h IN SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

;	implicit directive set ttl
example.com.	IN SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

;	implicit class from previous record
example.com.	   SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

;	implicit type from previous record
;	starts with the name of a class
example.com.		   in.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment
;	starts with the name of a type
example.com.	       ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

; implicit name from previous record, explicit type, class
			 1h IN SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment
			 
; implicit name from previous record, explicit type
				   SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

; implicit name from previous record
					   ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

;	non fqdn name
@					   ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment

;	split line rdata
@					   (										; comment
							ns.example.com.						; comment
							username.example.com.				; comment
							2007120710							; comment
							1d									; comment
							2h									; comment
							4w									; comment
							1h									; comment
					   )										; comment
						
;	combined data-field and split line data
@					   ns.example.com. (						; comment
							username.example.com.				; comment
							2007120710							; comment
							1d									; comment
							2h									; comment
							4w									; comment
							1h									; comment
					   )										; comment
						
;	multiple data-field and split line data
@					   ns.example.com. username.example.com. (	; comment
							2007120710							; comment
							1d									; comment
							2h									; comment
							4w									; comment
							1h									; comment
					   )										; comment

;	change the origin and have it appended the end of these records
$ORIGIN com.
example		 1h IN SOA ns.example.com. username.example.com. 2007120710 1d 2h 4w 1h ; comment
