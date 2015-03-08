module Transactions::Mail
  class Send < ::Transaction
    t_name :mail_send
    t_type 9001
    keep_going

    def params(mail)
      self.t_server = 1 # FIXME

      {
          to: mail.to,
          cc: mail.cc,
          bcc: mail.bcc,
          from: mail.from,
          reply_to: mail.reply_to,
          return_path: mail.return_path,
          message_id: mail.message_id,
          in_reply_to: mail.in_reply_to,
          references: mail.references,
          subject: mail.subject,
          text_plain: mail.text_plain,
          text_html: mail.text_html
      }
    end
  end
end
