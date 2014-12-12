(in-package :cl-user)
(defpackage project-gen.gen
  (:use :cl :trivial-types :anaphora)
  (:export :<file>
           :path
           :content
           :<option>
           :name
           :docstring
           :requiredp
           :default
           :<template>
           :name
           :options
           :files
           :<missing-required-option>
           :validate-options
           :render))
(in-package :project-gen.gen)

(defclass <file> ()
  ((path :reader path
         :initarg :path
         :type string
         :documentation "The path to the file, a Mustache template string.")
   (content :reader content
            :initarg :content
            :type string
            :documentation "The file's contents, a Mustache template string."))
  (:documentation "A file."))

(defclass <option> ()
  ((name :reader name
         :initarg :name
         :type keyword
         :documentation "The name of the option.")
   (docstring :reader docstring
              :initarg :docstring
              :type string
              :documentation "The option's documentation string.")
   (requiredp :reader requiredp
              :initarg :requiredp
              :initform nil
              :type boolean
              :documentation "Whether the option is required.")
   (processor :reader processor
              :initarg :processor
              :initform (lambda (x) x)
              :type function
              :documentation "A function used to process the value given to the option.")
   (default :reader default
            :initarg :default
            :documentation "The option's default value."))
  (:documentation "An option to a template."))

(defclass <template> ()
  ((name :reader name
         :initarg :name
         :type string
         :documentation "The template's descriptive name.")
   (docstring :reader docstring
              :initarg :docstring
              :type string
              :documentation "The template's documentation string.")
   (options :reader options
            :initarg :options
            :type (proper-list <option>)
            :documentation "A list of template options.")
   (files :reader files
          :initarg :files
          :type (proper-list files)
          :documentation "A list of files to template."))
  (:documentation "Represents a template."))

(define-condition <missing-required-option> (simple-error)
  ((option-name :reader option-name
                :initarg :option-name
                :type keyword
                :documentation "The name of the required option."))
  (:report
   (lambda (condition stream)
     (format stream "The option '~A' was required but was not supplied."
             (option-name condition)))))

(defmethod validate-options ((template <template>) (options list))
  "Take a plist of options, and validate it against the options in the template."
  (let ((final-options (list)))
    (loop for option in (options template) do
      (aif (getf options (name option))
           ;; Was the option supplied? If so, apply the option's processor to it
           ;; and add it to the `final-options` list
           (setf (getf final-options (name option))
                 (funcall (processor option) it))
           ;; Otherwise, check if it has a default value
           (if (slot-boundp option 'default)
               ;; Use this value
               (setf (getf final-options (name option))
                     (default option))
               ;; No default? If the option is required, signal an error
               (if (requiredp option)
                   (error '<missing-required-option>
                          :option-name (name option))))))
    final-options))

(defun render-template (template-string data)
  (with-output-to-string (str)
    (mustache:render
     template-string
     (loop for sublist on data by #'cddr collecting
       (cons (first sublist) (second sublist)))
     str)))

(defmethod render ((template <template>) (options list) (directory pathname))
  (let ((options (validate-options template options))
        (directory (fad:pathname-as-directory directory)))
    (loop for file in (files template) do
      (let* ((file-path (parse-namestring (render-template (path file) options)))
             (full-file-path (merge-pathnames
                              file-path
                              directory))
             (content (render-template (content file) options)))
        (ensure-directories-exist
         (fad:pathname-directory-pathname full-file-path))
        (with-open-file (output-stream full-file-path
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
          (write-string content output-stream))))))
